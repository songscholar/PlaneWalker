class_name LaunchEncounterRuntime
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Ids := preload("res://scripts/enemies/launch/launch_hostile_ids.gd")
const AffixRules := preload("res://scripts/enemies/launch/elite_affix_rules.gd")
const ROOT_FIELDS: Array[String] = ["id", "floor_id", "recipe_id", "room_type", "waves"]
const WAVE_FIELDS: Array[String] = ["id", "delay_frames", "warning_frames", "spawns"]
const SPAWN_FIELDS: Array[String] = ["id", "enemy_id", "spawn_slot_id", "spawn_offset", "elite", "affix_ids", "mechanism_ids"]
const IDENTITY_FIELDS: Array[String] = ["run_id", "room_id", "runtime_frame", "encounter_generation"]
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_version", "encounter_digest", "identity", "last_runtime_frame", "status", "wave_index",
	"wave_started_frame", "warning_frame", "spawn_frame", "pending_spawns", "roster",
	"defeat_ledger", "pending_work", "completion_published", "failure",
]
const WORK_BUDGETS := {"projectile": 32, "zone": 12, "construct": 8, "link": 3, "portal_pair": 1, "summon": 8}
const LIFE_STATES: Array[String] = ["ALIVE", "RECOVERING", "DORMANT", "FINAL"]
const LIVE_STATUSES: Array[String] = ["READY", "DELAY", "WARNING", "SPAWNING", "FIGHTING"]
const MAX_FRAME := 2147400000

var _encounter: Dictionary = {}
var _state: Dictionary = {}


func configure(encounter: Dictionary, identity: Dictionary) -> Dictionary:
	_encounter.clear()
	_state.clear()
	var normalized := normalize_encounter(encounter)
	if not normalized.ok:
		return normalized
	if not Contract.exact_fields(identity, IDENTITY_FIELDS) or not _stable_id(identity.run_id) or not _stable_id(identity.room_id) or not Contract.integer_in_range(identity.runtime_frame, 0, MAX_FRAME) or not Contract.integer_in_range(identity.encounter_generation, 1, MAX_FRAME):
		return _failure("identity", "invalid")
	_encounter = normalized.definition
	_state = {
		"schema_version": 1, "encounter_digest": JSON.stringify(_encounter).sha256_text(),
		"identity": {"run_id": identity.run_id, "room_id": identity.room_id, "runtime_frame": int(identity.runtime_frame), "encounter_generation": int(identity.encounter_generation)},
		"last_runtime_frame": int(identity.runtime_frame), "status": "READY", "wave_index": -1,
		"wave_started_frame": -1, "warning_frame": -1, "spawn_frame": -1,
		"pending_spawns": {}, "roster": {}, "defeat_ledger": {}, "pending_work": {},
		"completion_published": false, "failure": {},
	}
	return {"ok": true, "snapshot": snapshot(), "context": {}}


func advance_frame(runtime_frame: int, observations: Dictionary = {}) -> Dictionary:
	if _state.is_empty() or _state.status not in LIVE_STATUSES or runtime_frame != int(_state.last_runtime_frame) + 1 or runtime_frame > MAX_FRAME:
		return _failure("runtime_frame", "nonsequential_or_terminal")
	if not observations.is_empty():
		return _failure("observations", "unexpected_fields")
	var next := _state.duplicate(true)
	next.last_runtime_frame = runtime_frame
	var result := {"ok": true, "runtime_frame": runtime_frame, "wave_started": {}, "spawn_warnings": [], "spawn_requests": [], "encounter_completed": ""}
	if next.status == "READY" or (next.status == "FIGHTING" and _empty_work(next)):
		if int(next.wave_index) + 1 == _encounter.waves.size():
			next.status = "COMPLETE"
			next.completion_published = true
			result.encounter_completed = _encounter.id
			_state = next
			return result
		next.wave_index = int(next.wave_index) + 1
		var wave: Dictionary = _encounter.waves[next.wave_index]
		next.wave_started_frame = runtime_frame
		next.warning_frame = runtime_frame + int(wave.delay_frames)
		next.spawn_frame = int(next.warning_frame) + int(wave.warning_frames)
		next.status = "DELAY"
		result.wave_started = {"wave_index": next.wave_index, "wave_id": wave.id}
	if next.status == "DELAY" and runtime_frame == int(next.warning_frame):
		next.status = "WARNING"
		for spawn: Dictionary in _encounter.waves[next.wave_index].spawns:
			result.spawn_warnings.append({"spawn_definition": spawn.duplicate(true), "warning_frames": int(next.spawn_frame) - runtime_frame, "active_from_frame": runtime_frame, "spawn_frame": next.spawn_frame})
	if next.status == "WARNING" and runtime_frame == int(next.spawn_frame):
		next.status = "SPAWNING"
		for spawn: Dictionary in _encounter.waves[next.wave_index].spawns:
			next.pending_spawns[spawn.id] = spawn.duplicate(true)
			result.spawn_requests.append(spawn.duplicate(true))
	_state = next
	return result


func register_spawned(spawn_id: String, source_id: String) -> bool:
	if _state.is_empty() or _state.status != "SPAWNING" or not _state.pending_spawns.has(spawn_id) or not _stable_id(source_id) or _state.roster.has(source_id) or _state.defeat_ledger.has(source_id) or alive_count() >= 8:
		return false
	var spawn: Dictionary = _state.pending_spawns[spawn_id]
	_state.roster[source_id] = {"spawn_id": spawn_id, "enemy_id": spawn.enemy_id, "life_state": "ALIVE"}
	_state.pending_spawns.erase(spawn_id)
	if _state.pending_spawns.is_empty():
		_state.status = "FIGHTING"
	return true


func reject_spawn(spawn_id: String, reason: StringName) -> bool:
	if _state.is_empty() or _state.status != "SPAWNING" or not _state.pending_spawns.has(spawn_id) or not _stable_id(str(reason)):
		return false
	_state.status = "FAILED"
	_state.failure = {"code": "SPAWN_REJECTED", "spawn_id": spawn_id, "reason": str(reason)}
	return true


func set_life_state(source_id: String, life_state: String) -> bool:
	if _state.is_empty() or _state.status not in LIVE_STATUSES or not _state.roster.has(source_id) or life_state not in LIFE_STATES or _state.roster[source_id].life_state == "FINAL":
		return false
	_state.roster[source_id].life_state = life_state
	return true


func notify_entity_defeated(source_id: String, receipt_id: String) -> bool:
	if _state.is_empty() or _state.status not in LIVE_STATUSES or not _state.roster.has(source_id) or not _stable_id(receipt_id) or _state.roster[source_id].life_state not in ["ALIVE", "FINAL"]:
		return false
	for row: Dictionary in _state.defeat_ledger.values():
		if row.receipt_id == receipt_id:
			return false
	var actor: Dictionary = _state.roster[source_id]
	_state.defeat_ledger[source_id] = {"spawn_id": actor.spawn_id, "enemy_id": actor.enemy_id, "receipt_id": receipt_id, "frame": int(_state.last_runtime_frame)}
	_state.roster.erase(source_id)
	return true


func reserve_pending_work(work_id: String, kind: String, owner_source_id: String) -> bool:
	if _state.is_empty() or _state.status not in LIVE_STATUSES or not _stable_id(work_id) or not WORK_BUDGETS.has(kind) or _state.pending_work.has(work_id):
		return false
	if not _state.roster.has(owner_source_id) and not _state.defeat_ledger.has(owner_source_id):
		return false
	var count := 0
	for work: Dictionary in _state.pending_work.values():
		if work.kind == kind:
			count += 1
	if count >= int(WORK_BUDGETS[kind]):
		return false
	_state.pending_work[work_id] = {"kind": kind, "owner_source_id": owner_source_id}
	return true


func retire_pending_work(work_id: String) -> bool:
	if _state.is_empty() or _state.status not in LIVE_STATUSES or not _state.pending_work.has(work_id):
		return false
	_state.pending_work.erase(work_id)
	return true


func cancel(reason: StringName = &"cancelled") -> Dictionary:
	if _state.is_empty() or reason == &"":
		return _failure("cancel", "invalid")
	var sources: Array = _state.roster.keys()
	var work_ids: Array = _state.pending_work.keys()
	sources.sort()
	work_ids.sort()
	_state.status = "CANCELLED"
	_state.pending_spawns.clear()
	_state.roster.clear()
	_state.pending_work.clear()
	_state.completion_published = false
	_state.failure.clear()
	return {"ok": true, "reason": reason, "retired_sources": sources, "retired_work_ids": work_ids}


func alive_count() -> int:
	return _state.get("roster", {}).size()


func current_wave_index() -> int:
	return int(_state.get("wave_index", -1))


func is_active() -> bool:
	return _state.get("status", "") in LIVE_STATUSES


func can_complete() -> bool:
	return _state.get("status", "") == "COMPLETE" and bool(_state.get("completion_published", false))


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func configured_encounter() -> Dictionary:
	return _encounter.duplicate(true)


func can_restore_snapshot(value: Dictionary) -> bool:
	if _state.is_empty() or not Contract.exact_fields(value, SNAPSHOT_FIELDS) or typeof(value.schema_version) != TYPE_INT or value.schema_version != 1 or value.encounter_digest != _state.encounter_digest or value.identity != _state.identity:
		return false
	for field: String in ["last_runtime_frame", "wave_index", "wave_started_frame", "warning_frame", "spawn_frame"]:
		if typeof(value[field]) != TYPE_INT:
			return false
	if value.last_runtime_frame < int(value.identity.runtime_frame) or value.last_runtime_frame > MAX_FRAME or value.wave_index < -1 or value.wave_index >= _encounter.waves.size():
		return false
	if typeof(value.status) != TYPE_STRING or value.status not in LIVE_STATUSES + ["COMPLETE", "CANCELLED", "FAILED"] or typeof(value.completion_published) != TYPE_BOOL:
		return false
	for field: String in ["pending_spawns", "roster", "defeat_ledger", "pending_work", "failure"]:
		if not value[field] is Dictionary:
			return false
	if value.completion_published != (value.status == "COMPLETE") or (value.status == "FAILED") != not value.failure.is_empty():
		return false
	if value.status == "FAILED" and (not Contract.exact_fields(value.failure, ["code", "spawn_id", "reason"]) or value.failure.code != "SPAWN_REJECTED" or not _stable_id(value.failure.reason) or not value.pending_spawns.has(value.failure.spawn_id)):
		return false
	if value.wave_index == -1:
		return value.status in ["READY", "CANCELLED"] and value.wave_started_frame == -1 and value.warning_frame == -1 and value.spawn_frame == -1 and _empty_work(value) and value.defeat_ledger.is_empty() and value.last_runtime_frame == int(value.identity.runtime_frame)
	if value.status == "READY":
		return false
	var wave: Dictionary = _encounter.waves[value.wave_index]
	if value.wave_started_frame <= int(value.identity.runtime_frame) or value.wave_started_frame > value.last_runtime_frame or value.warning_frame != value.wave_started_frame + int(wave.delay_frames) or value.spawn_frame != value.warning_frame + int(wave.warning_frames):
		return false
	if value.status == "DELAY" and value.last_runtime_frame >= value.warning_frame:
		return false
	if value.status == "WARNING" and (value.last_runtime_frame < value.warning_frame or value.last_runtime_frame >= value.spawn_frame):
		return false
	if value.status in ["SPAWNING", "FIGHTING", "COMPLETE", "FAILED"] and value.last_runtime_frame < value.spawn_frame:
		return false
	if value.status == "SPAWNING" and value.pending_spawns.is_empty():
		return false
	if value.status in ["FIGHTING", "COMPLETE"] and not value.pending_spawns.is_empty():
		return false
	if value.status in ["DELAY", "WARNING", "CANCELLED"] and not _empty_work(value):
		return false
	if value.status == "COMPLETE" and (value.wave_index != _encounter.waves.size() - 1 or not _empty_work(value)):
		return false
	return _validate_rosters(value)


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	_state = value.duplicate(true)
	return true


func _validate_rosters(value: Dictionary) -> bool:
	var all_spawns: Dictionary = {}
	var current_spawns: Dictionary = {}
	var prior_spawns: Dictionary = {}
	for wave_index: int in range(int(value.wave_index) + 1):
		for spawn: Dictionary in _encounter.waves[wave_index].spawns:
			all_spawns[spawn.id] = spawn
			if wave_index == int(value.wave_index):
				current_spawns[spawn.id] = spawn
			else:
				prior_spawns[spawn.id] = spawn
	var bound_spawns: Dictionary = {}
	var receipts: Dictionary = {}
	if value.roster.size() > 8 or value.defeat_ledger.size() > 24 or value.pending_spawns.size() > 8:
		return false
	for source_id: Variant in value.roster:
		var row: Variant = value.roster[source_id]
		if not _stable_id(source_id) or not row is Dictionary or not Contract.exact_fields(row, ["spawn_id", "enemy_id", "life_state"]) or typeof(row.spawn_id) != TYPE_STRING or not current_spawns.has(row.spawn_id) or value.defeat_ledger.has(source_id) or bound_spawns.has(row.spawn_id):
			return false
		if row.enemy_id != current_spawns[row.spawn_id].enemy_id or typeof(row.life_state) != TYPE_STRING or row.life_state not in LIFE_STATES:
			return false
		bound_spawns[row.spawn_id] = true
	for source_id: Variant in value.defeat_ledger:
		var row: Variant = value.defeat_ledger[source_id]
		if not _stable_id(source_id) or not row is Dictionary or not Contract.exact_fields(row, ["spawn_id", "enemy_id", "receipt_id", "frame"]) or typeof(row.spawn_id) != TYPE_STRING or not all_spawns.has(row.spawn_id) or bound_spawns.has(row.spawn_id) or not _stable_id(row.receipt_id) or receipts.has(row.receipt_id) or typeof(row.frame) != TYPE_INT or row.frame < int(value.identity.runtime_frame) or row.frame > value.last_runtime_frame:
			return false
		if row.enemy_id != all_spawns[row.spawn_id].enemy_id:
			return false
		if current_spawns.has(row.spawn_id) and row.frame < value.spawn_frame:
			return false
		if prior_spawns.has(row.spawn_id) and row.frame >= value.wave_started_frame:
			return false
		bound_spawns[row.spawn_id] = true
		receipts[row.receipt_id] = true
	for spawn_id: Variant in value.pending_spawns:
		if typeof(spawn_id) != TYPE_STRING or not current_spawns.has(spawn_id) or bound_spawns.has(spawn_id) or value.pending_spawns[spawn_id] != current_spawns[spawn_id]:
			return false
		bound_spawns[spawn_id] = true
	if value.status in ["SPAWNING", "FIGHTING", "COMPLETE", "FAILED"] and bound_spawns.size() != all_spawns.size():
		return false
	if value.status in ["DELAY", "WARNING"]:
		if bound_spawns.size() != prior_spawns.size():
			return false
		for spawn_id: String in prior_spawns:
			if not bound_spawns.has(spawn_id):
				return false
	var budget_counts: Dictionary = {}
	for work_id: Variant in value.pending_work:
		var work: Variant = value.pending_work[work_id]
		if not _stable_id(work_id) or not work is Dictionary or not Contract.exact_fields(work, ["kind", "owner_source_id"]) or typeof(work.kind) != TYPE_STRING or not WORK_BUDGETS.has(work.kind) or not _stable_id(work.owner_source_id):
			return false
		if not value.roster.has(work.owner_source_id) and not value.defeat_ledger.has(work.owner_source_id):
			return false
		budget_counts[work.kind] = int(budget_counts.get(work.kind, 0)) + 1
		if budget_counts[work.kind] > int(WORK_BUDGETS[work.kind]):
			return false
	return true


static func normalize_encounter(source: Dictionary) -> Dictionary:
	if not Contract.exact_fields(source, ROOT_FIELDS) or not Contract.valid_id(source.id) or not Contract.valid_id(source.recipe_id) or typeof(source.floor_id) != TYPE_STRING or not Ids.FLOOR_IDS.has(source.floor_id) or typeof(source.room_type) != TYPE_STRING or source.room_type not in ["combat", "elite", "boss"]:
		return _failure("encounter", "invalid_fields")
	var floor_index := Ids.FLOOR_IDS.find(source.floor_id)
	var expected_id: String = Ids.BOSS_ENCOUNTER_IDS[floor_index] if source.room_type == "boss" else Ids.PROFILE_IDS[floor_index] + "." + source.recipe_id
	if source.id != expected_id or (source.room_type == "boss" and source.recipe_id != Ids.BOSS_IDS[floor_index]):
		return _failure("encounter.id", "identity_mismatch")
	if not source.waves is Array or source.waves.is_empty() or source.waves.size() > 3:
		return _failure("waves", "invalid_array")
	var waves: Array[Dictionary] = []
	var wave_ids: Dictionary = {}
	var spawn_ids: Dictionary = {}
	for candidate: Variant in source.waves:
		if not candidate is Dictionary or not Contract.exact_fields(candidate, WAVE_FIELDS) or not Contract.valid_id(candidate.id) or wave_ids.has(candidate.id):
			return _failure("waves", "invalid_identity")
		var minimum := 30 if floor_index == 0 else 23
		if source.room_type == "boss":
			minimum = 40 if floor_index == 0 else (25 if floor_index == 4 else 30)
		if not Contract.integer_in_range(candidate.delay_frames, 0, 600) or not Contract.integer_in_range(candidate.warning_frames, minimum, 600) or not candidate.spawns is Array or candidate.spawns.is_empty() or candidate.spawns.size() > 8:
			return _failure("waves", "invalid_timing_or_count")
		var spawns: Array[Dictionary] = []
		var elite_count := 0
		for spawn: Variant in candidate.spawns:
			if not spawn is Dictionary or not Contract.exact_fields(spawn, SPAWN_FIELDS) or not Contract.valid_id(spawn.id) or spawn_ids.has(spawn.id) or typeof(spawn.enemy_id) != TYPE_STRING:
				return _failure("spawns", "invalid_identity")
			if source.room_type == "boss":
				if spawn.enemy_id != Ids.BOSS_IDS[floor_index] or candidate.spawns.size() != 1 or source.waves.size() != 1:
					return _failure("spawns.enemy_id", "boss_identity_mismatch")
			elif not Ids.ENEMY_FLOORS.has(spawn.enemy_id) or int(Ids.ENEMY_FLOORS[spawn.enemy_id]) > floor_index + 1:
				return _failure("spawns.enemy_id", "unsupported")
			if typeof(spawn.spawn_slot_id) != TYPE_STRING or spawn.spawn_slot_id not in ["enemy_wave_primary", "boss_primary"] or spawn.spawn_slot_id != ("boss_primary" if source.room_type == "boss" else "enemy_wave_primary") or not Contract.valid_point(spawn.spawn_offset, 320) or typeof(spawn.elite) != TYPE_BOOL:
				return _failure("spawns", "invalid_slot_or_elite")
			if not spawn.affix_ids is Array or not spawn.mechanism_ids is Array or not spawn.mechanism_ids.is_empty():
				return _failure("spawns", "unsupported_mechanism")
			var required_affixes := (1 if floor_index < 2 else 2) if spawn.elite else 0
			if spawn.affix_ids.size() != required_affixes:
				return _failure("spawns.affix_ids", "invalid_count")
			if spawn.elite and not AffixRules.legal_for(spawn.enemy_id, floor_index + 1, spawn.affix_ids):
				return _failure("spawns.affix_ids", "excluded_or_wrong_floor")
			var seen_affixes: Array[String] = []
			for affix_id: Variant in spawn.affix_ids:
				if typeof(affix_id) != TYPE_STRING or not Ids.AFFIX_IDS.has(affix_id) or seen_affixes.has(affix_id):
					return _failure("spawns.affix_ids", "unsupported_or_duplicate")
				seen_affixes.append(affix_id)
			if spawn.elite:
				elite_count += 1
			var normalized_spawn: Dictionary = spawn.duplicate(true)
			normalized_spawn.spawn_offset = Contract.point(spawn.spawn_offset)
			spawns.append(normalized_spawn)
			spawn_ids[spawn.id] = true
		if elite_count > (2 if source.room_type == "elite" else 1) or (source.room_type == "boss" and elite_count > 0):
			return _failure("spawns.elite", "budget_exceeded")
		wave_ids[candidate.id] = true
		waves.append({"id": candidate.id, "delay_frames": int(candidate.delay_frames), "warning_frames": int(candidate.warning_frames), "spawns": spawns})
	return {"ok": true, "definition": {"id": source.id, "floor_id": source.floor_id, "recipe_id": source.recipe_id, "room_type": source.room_type, "waves": waves}, "context": {}}


static func _empty_work(value: Dictionary) -> bool:
	return value.roster.is_empty() and value.pending_spawns.is_empty() and value.pending_work.is_empty()


static func _stable_id(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.is_empty() or value.length() > 64 or value.strip_edges() != value:
		return false
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		if code < 33 or code > 126:
			return false
	return true


static func _failure(field: String, reason: String) -> Dictionary:
	return {"ok": false, "code": &"LAUNCH_ENCOUNTER_INVALID", "context": {"field": field, "reason": reason}}
