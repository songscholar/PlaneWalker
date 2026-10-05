extends RefCounted

const Meta := preload("res://scripts/progression/meta_progression_catalog.gd")
const Rules := preload("res://scripts/community/local_run_record_rules.gd")
const ACTIVE_FIELDS := ["sequence", "set_id", "run_id", "stage_index", "status", "elapsed_frames", "stage_frames", "damage_events", "stage_damage_events", "continued", "stages"]
const RESULT_FIELDS := ["sequence", "set_id", "run_id", "status", "elapsed_frames", "damage_events", "remaining_hp_milli", "continued", "stages", "terminal_digest"]
const STAGE_FIELDS := ["stage_index", "boss_id", "run_id", "hostile_source_id", "death_receipt", "frames", "damage_events", "remaining_hp_milli", "native_digest"]


static func empty(fingerprint: String) -> Dictionary:
	return {"schema_version": 1, "mode_fingerprint": fingerprint, "sequence": 0, "active": {}, "history": {}, "best": {}}


static func valid(value: Variant, catalog: RefCounted, profile_id: String) -> bool:
	if not Meta.exact_fields(value, ["schema_version", "mode_fingerprint", "sequence", "active", "history", "best"]) or value.schema_version != 1 or value.mode_fingerprint != catalog.fingerprint() or not Meta.bounded_int(value.sequence, 0, Meta.MAX_VALUE) or not value.active is Dictionary or not value.history is Dictionary or value.history.size() > 5 or not value.best is Dictionary or value.best.size() > 5:
		return false
	var sequences := {}
	for id: Variant in value.best:
		var best_value: Variant = value.best[id]
		if not id is String or not valid_result(best_value, catalog, profile_id) or best_value.set_id != id or best_value.status != "VICTORY" or best_value.continued or best_value.sequence > value.sequence:
			return false
	for id: Variant in value.history:
		if not id is String or catalog.definition(id).is_empty() or not value.history[id] is Array or value.history[id].size() > 10 or value.history[id].is_empty():
			return false
		var previous := 0
		for result: Variant in value.history[id]:
			if not valid_result(result, catalog, profile_id) or result.set_id != id or result.sequence <= previous or result.sequence > value.sequence or sequences.has(int(result.sequence)):
				return false
			previous = int(result.sequence)
			sequences[previous] = result
			if result.status == "VICTORY" and not result.continued:
				if not value.best.has(id) or ranks_before(result, value.best[id]):
					return false
	for id: Variant in value.best:
		var result: Variant = value.best[id]
		if not id is String or not valid_result(result, catalog, profile_id) or result.set_id != id or result.status != "VICTORY" or result.continued or result.sequence > value.sequence:
			return false
		if sequences.has(int(result.sequence)) and not Rules.same(sequences[int(result.sequence)], result):
			return false
		sequences[int(result.sequence)] = result
	if not value.active.is_empty():
		if not valid_active(value.active, catalog, profile_id) or value.active.sequence != value.sequence or sequences.has(int(value.active.sequence)):
			return false
	return value.sequence > 0 or Rules.same(value, empty(catalog.fingerprint()))


static func valid_active(value: Variant, catalog: RefCounted, profile_id: String) -> bool:
	if not Meta.exact_fields(value, ACTIVE_FIELDS) or not valid_identity(value, catalog, profile_id) or not Meta.bounded_int(value.stage_index, 0, 2) or value.status not in ["ACTIVE", "STAGE_CLEAR"] or not valid_metrics(value) or not Meta.bounded_int(value.stage_frames, 0, Meta.MAX_VALUE) or not Meta.bounded_int(value.stage_damage_events, 0, Meta.MAX_VALUE) or value.stage_frames > value.elapsed_frames or value.stage_damage_events > value.damage_events or value.status == "STAGE_CLEAR" and value.stage_index == 2:
		return false
	var expected: int = int(value.stage_index) + (1 if value.status == "STAGE_CLEAR" else 0)
	if not valid_stages(value.stages, catalog.definition(value.set_id), str(value.run_id)) or value.stages.size() != expected:
		return false
	var metrics := stage_totals(value.stages)
	if value.status == "STAGE_CLEAR":
		return value.elapsed_frames == metrics.frames and value.damage_events == metrics.damage_events and value.stage_frames == value.stages[-1].frames and value.stage_damage_events == value.stages[-1].damage_events
	return value.elapsed_frames == metrics.frames + value.stage_frames and value.damage_events == metrics.damage_events + value.stage_damage_events


static func valid_result(value: Variant, catalog: RefCounted, profile_id: String) -> bool:
	if not Meta.exact_fields(value, RESULT_FIELDS) or not valid_identity(value, catalog, profile_id) or not valid_metrics(value) or value.status not in ["VICTORY", "OBJECTIVE_FAILED", "DEFEAT", "ABANDON"] or not Meta.bounded_int(value.remaining_hp_milli, 0, 100000) or not value.terminal_digest is String:
		return false
	var definition: Dictionary = catalog.definition(value.set_id)
	if not valid_stages(value.stages, definition, str(value.run_id)):
		return false
	var metrics := stage_totals(value.stages)
	if metrics.frames > value.elapsed_frames or metrics.damage_events > value.damage_events:
		return false
	if value.status == "ABANDON":
		return value.stages.size() < 3 and value.terminal_digest.is_empty()
	if not Meta.fingerprint_valid(value.terminal_digest) or value.elapsed_frames < 1:
		return false
	if value.status == "DEFEAT":
		return value.remaining_hp_milli == 0 and value.stages.size() < 3
	if value.stages.is_empty() or value.remaining_hp_milli <= 0 or value.elapsed_frames != metrics.frames or value.damage_events != metrics.damage_events or value.remaining_hp_milli != value.stages[-1].remaining_hp_milli:
		return false
	var passed := objective_passed(definition, value.stages, int(value.elapsed_frames), int(value.damage_events))
	return value.stages.size() == 3 and passed if value.status == "VICTORY" else not passed


static func valid_identity(value: Dictionary, catalog: RefCounted, profile_id: String) -> bool:
	return Meta.bounded_int(value.sequence, 1, Meta.MAX_VALUE) and value.set_id is String and not catalog.definition(value.set_id).is_empty() and value.run_id == run_id(profile_id, value.set_id, int(value.sequence))


static func valid_metrics(value: Dictionary) -> bool:
	return Meta.bounded_int(value.elapsed_frames, 0, Meta.MAX_VALUE) and Meta.bounded_int(value.damage_events, 0, Meta.MAX_VALUE) and value.continued is bool


static func valid_stages(value: Variant, definition: Dictionary, run: String) -> bool:
	if not value is Array or value.size() > 3:
		return false
	for index: int in range(value.size()):
		var stage: Variant = value[index]
		var stage_run := stage_run_id(run, index)
		var source := "authored-" + stage_run.sha256_text().substr(0, 40)
		if not Meta.exact_fields(stage, STAGE_FIELDS) or stage.stage_index != index or stage.boss_id != definition.boss_ids[index] or stage.run_id != stage_run or stage.hostile_source_id != source or stage.death_receipt != "hostile_defeat:" + (stage_run + "|" + source).sha256_text().substr(0, 40) or not Meta.bounded_int(stage.frames, 1, Meta.MAX_VALUE) or not Meta.bounded_int(stage.damage_events, 0, Meta.MAX_VALUE) or not Meta.bounded_int(stage.remaining_hp_milli, 1, 100000) or not Meta.fingerprint_valid(stage.native_digest):
			return false
	return true


static func stage_totals(stages: Array) -> Dictionary:
	var frames := 0
	var damage := 0
	for stage: Dictionary in stages:
		frames += int(stage.frames)
		damage += int(stage.damage_events)
	return {"frames": frames, "damage_events": damage}


static func objective_passed(definition: Dictionary, stages: Array, elapsed: int, damage: int) -> bool:
	if stages.is_empty() or elapsed < 0 or damage < 0:
		return false
	var objective: Dictionary = definition.objective
	match objective.kind:
		"total_time": return elapsed <= int(objective.limit)
		"damage_events": return damage <= int(objective.limit)
		"no_damage": return damage == 0
		"stage_time":
			for stage: Dictionary in stages:
				if int(stage.frames) > int(objective.limit):
					return false
		"minimum_hp":
			for stage: Dictionary in stages:
				if int(stage.remaining_hp_milli) < int(objective.limit):
					return false
	return true


static func normalized(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	result.schema_version = int(result.schema_version)
	result.sequence = int(result.sequence)
	if not result.active.is_empty():
		_normalize(result.active, ["sequence", "stage_index", "elapsed_frames", "stage_frames", "damage_events", "stage_damage_events"])
		_normalize_stages(result.active.stages)
	for rows: Array in result.history.values():
		for row: Dictionary in rows:
			_normalize_result(row)
	for row: Dictionary in result.best.values():
		_normalize_result(row)
	return result


static func _normalize_result(value: Dictionary) -> void:
	_normalize(value, ["sequence", "elapsed_frames", "damage_events", "remaining_hp_milli"])
	_normalize_stages(value.stages)


static func _normalize_stages(stages: Array) -> void:
	for stage: Dictionary in stages:
		_normalize(stage, ["stage_index", "frames", "damage_events", "remaining_hp_milli"])


static func _normalize(value: Dictionary, fields: Array) -> void:
	for field: String in fields:
		value[field] = int(value[field])


static func ranks_before(left: Dictionary, right: Dictionary) -> bool:
	for field: String in ["elapsed_frames", "damage_events"]:
		if left[field] != right[field]:
			return left[field] < right[field]
	if left.remaining_hp_milli != right.remaining_hp_milli:
		return left.remaining_hp_milli > right.remaining_hp_milli
	return left.sequence < right.sequence


static func run_id(profile_id: String, set_id: String, sequence: int) -> String:
	return "authored-%s-%d-%s" % [profile_id, sequence, set_id]


static func stage_run_id(run: String, index: int) -> String:
	return "%s-stage-%d" % [run, index + 1]
