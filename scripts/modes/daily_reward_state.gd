extends RefCounted

const Meta := preload("res://scripts/progression/meta_progression_catalog.gd")
const Rules := preload("res://scripts/community/local_run_record_rules.gd")
const MAX_DAY := 2932896
const PRICES := {"daily_weapon_skin": 5, "daily_character_color": 10, "daily_archive_decoration": 20}
const ENTITLEMENTS := ["daily_participation_frame", "daily_walker_frame", "eternal_traveler"]
const FIELDS := ["schema_version", "tokens", "gold", "participation", "victory", "entitlements", "perfect_day", "owned_ids"]
const COUNTER_FIELDS := ["total", "last_day", "streak", "longest"]


static func empty() -> Dictionary:
	return {"schema_version": 1, "tokens": 0, "gold": 0, "participation": _counter(), "victory": _counter(), "entitlements": [], "perfect_day": -1, "owned_ids": []}


static func valid(value: Variant) -> bool:
	if not Meta.exact_fields(value, FIELDS) or value.schema_version != 1 or not _valid_counter(value.participation) or not _valid_counter(value.victory) or not value.entitlements is Array or not value.owned_ids is Array or not Meta.bounded_int(value.perfect_day, -1, MAX_DAY):
		return false
	if value.victory.total > value.participation.total or value.victory.last_day > value.participation.last_day or value.perfect_day > value.victory.last_day:
		return false
	var spent := 0
	var owned: Array = []
	for id: Variant in value.owned_ids:
		if not id is String or not PRICES.has(id) or owned.has(id):
			return false
		owned.append(id)
		spent += int(PRICES[id])
	owned.sort()
	return Rules.same(owned, value.owned_ids) and Rules.same(_entitlements(value), value.entitlements) and value.tokens == value.participation.total - spent and value.tokens >= 0 and value.gold == value.victory.total * 50


static func award(value: Dictionary, day: int, status: String, damage_events: int) -> Dictionary:
	if not valid(value) or day < 0 or day > MAX_DAY or day < int(value.participation.last_day) or status not in ["VICTORY", "DEFEAT", "ABANDON"] or damage_events < -1 or damage_events > Meta.MAX_VALUE:
		return value.duplicate(true)
	var result := value.duplicate(true)
	if day > int(result.participation.last_day):
		_credit(result.participation, day)
		result.tokens += 1
	if status == "VICTORY":
		if day > int(result.victory.last_day):
			_credit(result.victory, day)
			result.gold += 50
		if damage_events == 0:
			result.perfect_day = day
	result.entitlements = _entitlements(result)
	return result


static func purchase(value: Dictionary, id: String) -> Dictionary:
	if not valid(value) or not PRICES.has(id) or value.owned_ids.has(id) or value.tokens < PRICES[id]:
		return {"ok": false, "state": value.duplicate(true)}
	var result := value.duplicate(true)
	result.tokens -= int(PRICES[id])
	result.owned_ids.append(id)
	result.owned_ids.sort()
	return {"ok": true, "state": result}


static func normalized(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	for field: String in ["schema_version", "tokens", "gold", "perfect_day"]:
		result[field] = int(result[field])
	for field: String in ["participation", "victory"]:
		for key: String in COUNTER_FIELDS:
			result[field][key] = int(result[field][key])
	return result


static func _counter() -> Dictionary:
	return {"total": 0, "last_day": -1, "streak": 0, "longest": 0}


static func _valid_counter(value: Variant) -> bool:
	if not Meta.exact_fields(value, COUNTER_FIELDS) or not Meta.bounded_int(value.total, 0, MAX_DAY + 1) or not Meta.bounded_int(value.last_day, -1, MAX_DAY) or not Meta.bounded_int(value.streak, 0, MAX_DAY + 1) or not Meta.bounded_int(value.longest, 0, MAX_DAY + 1):
		return false
	if value.total == 0:
		return Rules.same(value, _counter())
	return value.last_day >= 0 and value.total <= value.last_day + 1 and value.streak >= 1 and value.streak <= value.longest and value.longest <= value.total


static func _credit(counter: Dictionary, day: int) -> void:
	counter.streak = int(counter.streak) + 1 if day == int(counter.last_day) + 1 else 1
	counter.total += 1
	counter.last_day = day
	counter.longest = maxi(int(counter.longest), int(counter.streak))


static func _entitlements(value: Dictionary) -> Array:
	var result: Array = []
	if value.participation.longest >= 7:
		result.append("daily_participation_frame")
	if value.victory.longest >= 7:
		result.append("daily_walker_frame")
	if value.participation.longest >= 30:
		result.append("eternal_traveler")
	return result
