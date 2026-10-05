extends RefCounted

const Meta := preload("res://scripts/progression/meta_progression_catalog.gd")
const Catalog := preload("res://scripts/modes/daily_boss_catalog.gd")
const Rules := preload("res://scripts/community/local_run_record_rules.gd")
const RESULT_FIELDS := ["attempt", "run_id", "status", "elapsed_frames", "remaining_hp_milli", "hostile_source_id", "death_receipt", "native_digest"]


static func empty(fingerprint: String) -> Dictionary:
	return {"schema_version": 1, "mode_fingerprint": fingerprint, "latest_day": -1, "days": [], "active": {}}


static func valid(value: Variant, catalog: RefCounted, profile_id: String) -> bool:
	if not Meta.exact_fields(value, ["schema_version", "mode_fingerprint", "latest_day", "days", "active"]) or value.schema_version != 1 or value.mode_fingerprint != catalog.fingerprint() or not Meta.bounded_int(value.latest_day, -1, Catalog.MAX_DAY) or not value.days is Array or value.days.size() > 31 or not value.active is Dictionary:
		return false
	var active: Dictionary = value.active
	if not active.is_empty():
		if not Meta.exact_fields(active, ["day_index", "attempt", "run_id", "definition", "elapsed_frames"]) or not Meta.bounded_int(active.day_index, 0, Catalog.MAX_DAY) or not Meta.bounded_int(active.attempt, 1, 3) or not Meta.bounded_int(active.elapsed_frames, 0, Meta.MAX_VALUE) or not catalog.valid_projection(active.definition) or active.definition.day_index != active.day_index or active.run_id != run_id(profile_id, int(active.day_index), int(active.attempt)):
			return false
	var previous := -1
	var active_found := active.is_empty()
	for row: Variant in value.days:
		if not Meta.exact_fields(row, ["day_index", "day_key", "attempts", "results", "best"]) or not Meta.bounded_int(row.day_index, 0, Catalog.MAX_DAY) or row.day_index <= previous or row.day_key != catalog.projection_for_day(int(row.day_index)).day_key or not Meta.bounded_int(row.attempts, 1, 3) or not row.results is Array or not row.best is Dictionary:
			return false
		previous = int(row.day_index)
		var owns: bool = not active.is_empty() and active.day_index == row.day_index
		if row.attempts != row.results.size() + (1 if owns else 0) or owns and active.attempt != row.attempts:
			return false
		active_found = active_found or owns
		for index: int in range(row.results.size()):
			if not valid_result(row.results[index], profile_id, int(row.day_index), index + 1):
				return false
		if not Rules.same(row.best, best(row.results)):
			return false
	return active_found and value.latest_day == previous and (not value.days.is_empty() or Rules.same(value, empty(catalog.fingerprint())))


static func valid_result(value: Variant, profile_id: String, day: int, attempt: int) -> bool:
	var run := run_id(profile_id, day, attempt)
	var source := "daily-" + run.sha256_text().substr(0, 40)
	if not Meta.exact_fields(value, RESULT_FIELDS) or value.attempt != attempt or value.run_id != run or value.status not in ["VICTORY", "DEFEAT", "ABANDON"] or not Meta.bounded_int(value.elapsed_frames, 0, Meta.MAX_VALUE) or not Meta.bounded_int(value.remaining_hp_milli, 0, 100000) or value.hostile_source_id != source or not value.death_receipt is String or not value.native_digest is String:
		return false
	if value.status == "ABANDON":
		return value.death_receipt.is_empty() and value.native_digest.is_empty()
	if not Meta.fingerprint_valid(value.native_digest) or value.elapsed_frames < 1:
		return false
	if value.status == "DEFEAT":
		return value.remaining_hp_milli == 0 and value.death_receipt.is_empty()
	return value.remaining_hp_milli > 0 and value.death_receipt == "hostile_defeat:" + (run + "|" + source).sha256_text().substr(0, 40)


static func normalized(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	for field: String in ["schema_version", "latest_day"]:
		result[field] = int(result[field])
	for day: Dictionary in result.days:
		for field: String in ["day_index", "attempts"]:
			day[field] = int(day[field])
		for row: Dictionary in day.results:
			_normalize_result(row)
		if not day.best.is_empty():
			_normalize_result(day.best)
	if not result.active.is_empty():
		for field: String in ["day_index", "attempt", "elapsed_frames"]:
			result.active[field] = int(result.active[field])
		for field: String in ["day_index", "reset_at", "seed"]:
			result.active.definition[field] = int(result.active.definition[field])
	return result


static func _normalize_result(value: Dictionary) -> void:
	for field: String in ["attempt", "elapsed_frames", "remaining_hp_milli"]:
		value[field] = int(value[field])


static func best(results: Array) -> Dictionary:
	var result: Dictionary = {}
	for value: Dictionary in results:
		if result.is_empty() or ranks_before(value, result):
			result = value.duplicate(true)
	return result


static func ranks_before(left: Dictionary, right: Dictionary) -> bool:
	var statuses := ["VICTORY", "DEFEAT", "ABANDON"]
	if left.status != right.status:
		return statuses.find(left.status) < statuses.find(right.status)
	if left.status == "VICTORY" and left.elapsed_frames != right.elapsed_frames:
		return left.elapsed_frames < right.elapsed_frames
	if left.remaining_hp_milli != right.remaining_hp_milli:
		return left.remaining_hp_milli > right.remaining_hp_milli
	return left.attempt < right.attempt


static func run_id(profile_id: String, day: int, attempt: int) -> String:
	return "daily-boss-%s-%d-%d" % [profile_id, day, attempt]
