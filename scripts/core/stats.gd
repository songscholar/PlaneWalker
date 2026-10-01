class_name Stats
extends Resource

const PROFILE_FIELDS: Array[String] = [
	"max_hp",
	"attack",
	"defense",
	"move_speed",
	"attack_speed",
	"crit_chance",
	"crit_multiplier",
	"time_energy_max",
	"time_energy_regen",
]

@export var max_hp: float = 200.0
@export var attack: float = 30.0
@export var defense: float = 0.0
@export var move_speed: float = 220.0
@export var attack_speed: float = 1.0
@export var crit_chance: float = 0.05
@export var crit_multiplier: float = 1.5
@export var time_energy_max: float = 100.0
@export var time_energy_regen: float = 2.0


func apply_profile(profile: Dictionary) -> bool:
	if profile.size() != PROFILE_FIELDS.size():
		return false
	var normalized: Dictionary = {}
	for field: String in PROFILE_FIELDS:
		if not profile.has(field):
			return false
		var value: Variant = profile[field]
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return false
		normalized[field] = float(value)
	if (
		float(normalized["max_hp"]) <= 0.0
		or float(normalized["attack"]) < 0.0
		or float(normalized["defense"]) < 0.0
		or float(normalized["move_speed"]) <= 0.0
		or float(normalized["attack_speed"]) <= 0.0
		or float(normalized["crit_chance"]) < 0.0
		or float(normalized["crit_chance"]) > 1.0
		or float(normalized["crit_multiplier"]) < 1.0
		or float(normalized["time_energy_max"]) <= 0.0
		or float(normalized["time_energy_regen"]) < 0.0
	):
		return false
	max_hp = float(normalized["max_hp"])
	attack = float(normalized["attack"])
	defense = float(normalized["defense"])
	move_speed = float(normalized["move_speed"])
	attack_speed = float(normalized["attack_speed"])
	crit_chance = float(normalized["crit_chance"])
	crit_multiplier = float(normalized["crit_multiplier"])
	time_energy_max = float(normalized["time_energy_max"])
	time_energy_regen = float(normalized["time_energy_regen"])
	return true


func snapshot() -> Dictionary:
	return {
		"max_hp": max_hp,
		"attack": attack,
		"defense": defense,
		"move_speed": move_speed,
		"attack_speed": attack_speed,
		"crit_chance": crit_chance,
		"crit_multiplier": crit_multiplier,
		"time_energy_max": time_energy_max,
		"time_energy_regen": time_energy_regen,
	}
