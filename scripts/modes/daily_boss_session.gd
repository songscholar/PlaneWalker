extends RefCounted

const Meta := preload("res://scripts/progression/meta_progression_catalog.gd")
const Catalog := preload("res://scripts/modes/daily_boss_catalog.gd")
const Rules := preload("res://scripts/community/local_run_record_rules.gd")
const Rewards := preload("res://scripts/modes/daily_reward_state.gd")
const RESULT_FIELDS := ["attempt", "run_id", "status", "elapsed_frames", "remaining_hp_milli", "hostile_source_id", "death_receipt", "native_digest"]


static func empty(fingerprint: String) -> Dictionary:
	return {"schema_version": 2, "mode_fingerprint": fingerprint, "latest_day": -1, "days": [], "active": {}, "archived_rewards": Rewards.empty(), "reward_state": Rewards.empty()}


static func valid(value: Variant, catalog: RefCounted, profile_id: String) -> bool:
	if not _valid_structure(value, catalog, profile_id, false) or not Rewards.valid(value.archived_rewards) or not value.archived_rewards.owned_ids.is_empty() or not Rewards.valid(value.reward_state):
		return false
	if not value.days.is_empty() and int(value.archived_rewards.participation.last_day) >= int(value.days[0].day_index):
		return false
	var expected: Dictionary = value.archived_rewards.duplicate(true)
	for day: Dictionary in value.days:
		for result: Dictionary in day.results:
			expected = Rewards.award(expected, int(day.day_index), result.status, int(result.damage_events))
	for id: String in value.reward_state.owned_ids:
		var bought := Rewards.purchase(expected, id)
		if not bought.ok:
			return false
		expected = bought.state
	return Rules.same(value.reward_state, expected)


static func _valid_structure(value: Variant, catalog: RefCounted, profile_id: String, legacy: bool) -> bool:
	var fields := ["schema_version", "mode_fingerprint", "latest_day", "days", "active"]
	if not legacy:
		fields.append_array(["archived_rewards", "reward_state"])
	if not Meta.exact_fields(value, fields) or value.schema_version != (1 if legacy else 2) or value.mode_fingerprint != catalog.fingerprint() and (not legacy or value.mode_fingerprint != catalog.legacy_fingerprint()) or not Meta.bounded_int(value.latest_day, -1, Catalog.MAX_DAY) or not value.days is Array or value.days.size() > 31 or not value.active is Dictionary:
		return false
	var active: Dictionary = value.active
	if not active.is_empty():
		var active_fields := ["day_index", "attempt", "run_id", "definition", "elapsed_frames"]
		if not legacy:
			active_fields.append("damage_events")
		if not Meta.exact_fields(active, active_fields) or not Meta.bounded_int(active.day_index, 0, Catalog.MAX_DAY) or not Meta.bounded_int(active.attempt, 1, 3) or not Meta.bounded_int(active.elapsed_frames, 0, Meta.MAX_VALUE) or not legacy and not Meta.bounded_int(active.damage_events, -1, Meta.MAX_VALUE) or not catalog.valid_projection(active.definition) or active.definition.day_index != active.day_index or active.run_id != run_id(profile_id, int(active.day_index), int(active.attempt)):
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
			if not valid_result(row.results[index], profile_id, int(row.day_index), index + 1, legacy):
				return false
		if not Rules.same(row.best, best(row.results)):
			return false
	return active_found and value.latest_day == previous and (not value.days.is_empty() or active.is_empty())


static func valid_result(value: Variant, profile_id: String, day: int, attempt: int, legacy: bool = false) -> bool:
	var run := run_id(profile_id, day, attempt)
	var source := "daily-" + run.sha256_text().substr(0, 40)
	var fields := RESULT_FIELDS.duplicate()
	if not legacy:
		fields.append("damage_events")
	if not Meta.exact_fields(value, fields) or value.attempt != attempt or value.run_id != run or value.status not in ["VICTORY", "DEFEAT", "ABANDON"] or not Meta.bounded_int(value.elapsed_frames, 0, Meta.MAX_VALUE) or not Meta.bounded_int(value.remaining_hp_milli, 0, 100000) or not legacy and not Meta.bounded_int(value.damage_events, -1, Meta.MAX_VALUE) or value.hostile_source_id != source or not value.death_receipt is String or not value.native_digest is String:
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
		for field: String in ["day_index", "attempt", "elapsed_frames", "damage_events"]:
			result.active[field] = int(result.active[field])
		for field: String in ["day_index", "reset_at", "seed"]:
			result.active.definition[field] = int(result.active.definition[field])
	result.archived_rewards = Rewards.normalized(result.archived_rewards)
	result.reward_state = Rewards.normalized(result.reward_state)
	return result


static func _normalize_result(value: Dictionary) -> void:
	for field: String in ["attempt", "elapsed_frames", "remaining_hp_milli", "damage_events"]:
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


static func migrate(value: Variant, catalog: RefCounted, profile_id: String) -> Dictionary:
	if valid(value, catalog, profile_id):
		return {"ok": true, "state": normalized(value)}
	if value is Dictionary and value.get("schema_version") == 2 and value.get("mode_fingerprint") == catalog.legacy_fingerprint():
		var upgraded: Dictionary = value.duplicate(true)
		upgraded.mode_fingerprint = catalog.fingerprint()
		if valid(upgraded, catalog, profile_id):
			return {"ok": true, "state": normalized(upgraded)}
	if not _valid_structure(value, catalog, profile_id, true):
		return {"ok": false, "state": {}}
	var result: Dictionary = value.duplicate(true)
	result.schema_version = 2
	result.mode_fingerprint = catalog.fingerprint()
	result["archived_rewards"] = Rewards.empty()
	result["reward_state"] = Rewards.empty()
	if not result.active.is_empty():
		result.active["damage_events"] = -1
	for day: Dictionary in result.days:
		for row: Dictionary in day.results:
			row["damage_events"] = -1
			result.reward_state = Rewards.award(result.reward_state, int(day.day_index), row.status, -1)
		day.best = best(day.results)
	return {"ok": valid(result, catalog, profile_id), "state": normalized(result)}


static func trim_archive(state: Dictionary) -> void:
	while state.days.size() > 31:
		var day: Dictionary = state.days.pop_front()
		for row: Dictionary in day.results:
			state.archived_rewards = Rewards.award(state.archived_rewards, int(day.day_index), row.status, int(row.damage_events))


static func validated_reward_aggregate(payload: Variant, owner_id: String, mode_fingerprint: String, registry: RefCounted) -> Dictionary:
	var catalog := Catalog.new()
	if not Meta.exact_fields(payload, ["daily_session"]) or not catalog.configure(registry) or catalog.fingerprint() != mode_fingerprint or not valid(payload.daily_session, catalog, owner_id):
		return {"ok": false}
	var reward: Dictionary = payload.daily_session.reward_state
	return {"ok": true, "source_id": "daily:%s:%s" % [owner_id, mode_fingerprint], "lifetime_participation": int(reward.participation.total), "lifetime_victories": int(reward.victory.total), "entitlement_ids": reward.entitlements.duplicate(), "owned_ids": reward.owned_ids.duplicate()}
