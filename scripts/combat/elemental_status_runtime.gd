class_name ElementalStatusRuntime
extends RefCounted

const VALID_EFFECTS := {
	&"burn": true,
	&"slow": true,
	&"freeze": true,
	&"shock": true,
	&"blind": true,
}
const DEFAULT_SLOW_FLOOR := 0.30
const MAX_SHOCK_DAMAGE_BONUS := 2.0
const HASH_MODULUS := 2147483647

var _entries: Dictionary = {}
var _deterministic_seed: int = 0
var _slow_floor_multiplier: float = DEFAULT_SLOW_FLOOR
var _attack_slow_floor_multiplier: float = DEFAULT_SLOW_FLOOR


func configure(
	deterministic_seed: int,
	slow_floor_multiplier: float = DEFAULT_SLOW_FLOOR,
	attack_slow_floor_multiplier: float = -1.0
) -> void:
	_deterministic_seed = deterministic_seed
	if not is_finite(slow_floor_multiplier):
		_slow_floor_multiplier = DEFAULT_SLOW_FLOOR
	else:
		_slow_floor_multiplier = clampf(slow_floor_multiplier, 0.1, 1.0)
	if attack_slow_floor_multiplier < 0.0:
		_attack_slow_floor_multiplier = _slow_floor_multiplier
	elif not is_finite(attack_slow_floor_multiplier):
		_attack_slow_floor_multiplier = DEFAULT_SLOW_FLOOR
	else:
		_attack_slow_floor_multiplier = clampf(attack_slow_floor_multiplier, 0.1, 1.0)


func apply_status(
	effect_id: StringName,
	source_id: StringName,
	generation: int,
	duration_frames: int,
	magnitude: float = 1.0,
	tick_interval_frames: int = 30,
	attack_speed_multiplier: float = -1.0,
	damage_source: Node = null,
	damage_attacker: Node = null
) -> bool:
	if not _is_valid_application(
		effect_id,
		source_id,
		generation,
		duration_frames,
		magnitude,
		tick_interval_frames,
		attack_speed_multiplier
	):
		return false
	var key := _status_key(effect_id, source_id, generation)
	if _entries.has(key):
		var existing: Dictionary = _entries[key]
		existing["remaining_frames"] = maxi(
			int(existing.get("remaining_frames", 0)),
			duration_frames
		)
		_entries[key] = existing
		return true
	_entries[key] = {
		"key": key,
		"effect_id": effect_id,
		"source_id": source_id,
		"generation": generation,
		"remaining_frames": duration_frames,
		"elapsed_frames": 0,
		"magnitude": magnitude,
		"attack_speed_multiplier": (
			attack_speed_multiplier
			if effect_id == &"slow" and attack_speed_multiplier >= 0.0
			else magnitude
		),
		"tick_interval_frames": tick_interval_frames if effect_id == &"burn" else 0,
		"damage_source": damage_source if effect_id == &"burn" else null,
		"damage_attacker": damage_attacker if effect_id == &"burn" else null,
	}
	return true


func remove_status(effect_id: StringName, source_id: StringName, generation: int) -> bool:
	var key := _status_key(effect_id, source_id, generation)
	if not _entries.has(key):
		return false
	_entries.erase(key)
	return true


func clear_owned(source_id: StringName, generation: int = -1) -> int:
	if source_id == &"":
		return 0
	var removed := 0
	for key: String in _sorted_keys():
		var entry: Dictionary = _entries.get(key, {})
		if StringName(str(entry.get("source_id", ""))) != source_id:
			continue
		if generation >= 0 and int(entry.get("generation", -1)) != generation:
			continue
		_entries.erase(key)
		removed += 1
	return removed


func clear_all() -> int:
	var removed := _entries.size()
	_entries.clear()
	return removed


func reset_runtime_state() -> void:
	clear_all()


func advance_frame() -> Dictionary:
	var burn_damage := 0.0
	var burn_ticks: Array[Dictionary] = []
	var expired: Array[Dictionary] = []
	for key: String in _sorted_keys():
		if not _entries.has(key):
			continue
		var entry: Dictionary = _entries[key]
		entry["elapsed_frames"] = int(entry.get("elapsed_frames", 0)) + 1
		if entry.get("effect_id") == &"burn":
			var interval := maxi(1, int(entry.get("tick_interval_frames", 1)))
			if int(entry["elapsed_frames"]) % interval == 0:
				var tick_damage := maxf(0.0, float(entry.get("magnitude", 0.0)))
				burn_damage += tick_damage
				burn_ticks.append({
					"effect_id": entry.get("effect_id"),
					"source_id": entry.get("source_id"),
					"generation": entry.get("generation"),
					"damage": tick_damage,
					"damage_source": entry.get("damage_source"),
					"damage_attacker": entry.get("damage_attacker"),
				})
		entry["remaining_frames"] = int(entry.get("remaining_frames", 0)) - 1
		if int(entry["remaining_frames"]) <= 0:
			expired.append(entry.duplicate(true))
			_entries.erase(key)
		else:
			_entries[key] = entry
	return {
		"burn_damage": burn_damage,
		"burn_ticks": burn_ticks,
		"expired": expired,
	}


func has_status(effect_id: StringName, source_id: StringName, generation: int) -> bool:
	return _entries.has(_status_key(effect_id, source_id, generation))


func is_effect_active(effect_id: StringName) -> bool:
	for entry_value: Variant in _entries.values():
		if entry_value is Dictionary and (entry_value as Dictionary).get("effect_id") == effect_id:
			return true
	return false


func remaining_frames(effect_id: StringName, source_id: StringName, generation: int) -> int:
	var entry: Dictionary = _entries.get(_status_key(effect_id, source_id, generation), {})
	return int(entry.get("remaining_frames", 0))


func source_count(effect_id: StringName = &"") -> int:
	if effect_id == &"":
		return _entries.size()
	var count := 0
	for entry_value: Variant in _entries.values():
		if entry_value is Dictionary and (entry_value as Dictionary).get("effect_id") == effect_id:
			count += 1
	return count


func slow_multiplier() -> float:
	var multiplier := 1.0
	for entry_value: Variant in _entries.values():
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		if entry.get("effect_id") == &"slow":
			multiplier = minf(multiplier, float(entry.get("magnitude", 1.0)))
	return maxf(_slow_floor_multiplier, multiplier)


func is_frozen() -> bool:
	return is_effect_active(&"freeze")


func attack_speed_multiplier() -> float:
	var multiplier := 1.0
	for entry_value: Variant in _entries.values():
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		if entry.get("effect_id") == &"slow":
			multiplier = minf(
				multiplier,
				float(entry.get("attack_speed_multiplier", entry.get("magnitude", 1.0)))
			)
	return maxf(_attack_slow_floor_multiplier, multiplier)


func shock_damage_bonus() -> float:
	var total_bonus := 0.0
	for entry_value: Variant in _entries.values():
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		if entry.get("effect_id") == &"shock":
			total_bonus += maxf(0.0, float(entry.get("magnitude", 0.0)))
	return minf(total_bonus, MAX_SHOCK_DAMAGE_BONUS)


func blind_chance() -> float:
	var success_product := 1.0
	for entry_value: Variant in _entries.values():
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		if entry.get("effect_id") == &"blind":
			success_product *= 1.0 - clampf(float(entry.get("magnitude", 0.0)), 0.0, 1.0)
	return clampf(1.0 - success_product, 0.0, 0.95)


func should_blind_miss(action_sequence: int) -> bool:
	var chance := blind_chance()
	if chance <= 0.0:
		return false
	var blind_keys: Array[String] = []
	for key: String in _sorted_keys():
		var entry: Dictionary = _entries.get(key, {})
		if entry.get("effect_id") == &"blind":
			blind_keys.append("%s@%.6f" % [key, float(entry.get("magnitude", 0.0))])
	var material := "%d|%d|%s" % [_deterministic_seed, action_sequence, "|".join(blind_keys)]
	var roll := float(_stable_hash(material)) / float(HASH_MODULUS)
	return roll < chance


func snapshot() -> Dictionary:
	var effects: Array[Dictionary] = []
	for key: String in _sorted_keys():
		var entry: Dictionary = _entries.get(key, {})
		if not entry.is_empty():
			var serialized := entry.duplicate(true)
			serialized.erase("damage_source")
			serialized.erase("damage_attacker")
			effects.append(serialized)
	return {
		"schema_version": 1,
		"source_count": effects.size(),
		"slow_multiplier": slow_multiplier(),
		"attack_speed_multiplier": attack_speed_multiplier(),
		"frozen": is_frozen(),
		"shock_damage_bonus": shock_damage_bonus(),
		"blind_chance": blind_chance(),
		"effects": effects,
	}


func _is_valid_application(
	effect_id: StringName,
	source_id: StringName,
	generation: int,
	duration_frames: int,
	magnitude: float,
	tick_interval_frames: int,
	attack_speed_multiplier: float
) -> bool:
	if (
		not VALID_EFFECTS.has(effect_id)
		or source_id == &""
		or generation < 0
		or duration_frames <= 0
		or not is_finite(magnitude)
	):
		return false
	match effect_id:
		&"burn":
			return magnitude > 0.0 and tick_interval_frames > 0
		&"slow":
			return (
				magnitude > 0.0
				and magnitude <= 1.0
				and (
					attack_speed_multiplier < 0.0
					or (
						is_finite(attack_speed_multiplier)
						and attack_speed_multiplier > 0.0
						and attack_speed_multiplier <= 1.0
					)
				)
			)
		&"freeze":
			return magnitude >= 0.0
		&"shock":
			return magnitude > 0.0 and magnitude <= MAX_SHOCK_DAMAGE_BONUS
		&"blind":
			return magnitude > 0.0 and magnitude <= 1.0
	return false


func _status_key(effect_id: StringName, source_id: StringName, generation: int) -> String:
	var effect_text := str(effect_id)
	var source_text := str(source_id)
	return "%d:%s|%d:%s|%d" % [
		effect_text.length(),
		effect_text,
		source_text.length(),
		source_text,
		generation,
	]


func _sorted_keys() -> Array[String]:
	var keys: Array[String] = []
	for key_value: Variant in _entries.keys():
		keys.append(str(key_value))
	keys.sort()
	return keys


func _stable_hash(value: String) -> int:
	var result := 5381
	for byte: int in value.to_utf8_buffer():
		result = int((result * 33 + byte) % HASH_MODULUS)
	return result
