class_name RunSettlementAuthority
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const MetaProjection := preload("res://scripts/progression/meta_run_projection.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const Phase := preload("res://scripts/application/run_phase.gd")
const Lifetime := preload("res://scripts/events/event_modifier_lifetime.gd")
const Resources := preload("res://scripts/events/event_resource_authority.gd")
const SOURCE_FIELDS := ["schema_id", "source_id", "run_id", "launch_sequence", "floor_id", "node_id", "kind", "payload"]
const SOURCE_TYPE := "meta_settlement_source_v1"
const BOSS_ORDER := ["ruin_king", "forest_heart", "time_sovereign", "forge_colossus", "void_throne"]
const LAUNCH_FIELDS := ["schema_id", "sequence", "run_id", "difficulty", "seed", "character_id", "weapon_id", "time_abilities", "projection_digest"]

var _catalog: RefCounted
var _boss_by_floor: Dictionary = {}


func configure(catalog: RefCounted, boss_by_floor: Dictionary) -> bool:
	var validator = Profile.new()
	if not validator.configure(catalog) or not Catalog.exact_fields(boss_by_floor, Envelope.FLOOR_IDS):
		return false
	var seen: Array = []
	for floor_id: String in Envelope.FLOOR_IDS:
		if boss_by_floor[floor_id] != BOSS_ORDER[Envelope.FLOOR_IDS.find(floor_id)] or seen.has(boss_by_floor[floor_id]):
			return false
		seen.append(boss_by_floor[floor_id])
	_catalog = catalog
	_boss_by_floor = boss_by_floor.duplicate(true)
	return true


func verified_run_sources(launch: Dictionary, run_snapshot: Dictionary) -> Dictionary:
	if _catalog == null or not Catalog.exact_fields(launch, LAUNCH_FIELDS) or launch.schema_id != "meta_launch_receipt_v1" or not Catalog.stable_id(launch.run_id) or not Catalog.bounded_int(launch.sequence, 1, Catalog.MAX_VALUE) or not Catalog.bounded_int(launch.seed, 0, Catalog.MAX_VALUE) or launch.difficulty not in ["normal", "hard", "nightmare"] or launch.character_id not in Catalog.CHARACTER_IDS or launch.weapon_id not in Catalog.WEAPON_IDS or not launch.time_abilities is Array or launch.time_abilities.size() != 2 or launch.time_abilities[0] not in Catalog.TIME_IDS or launch.time_abilities[1] not in Catalog.TIME_IDS or launch.time_abilities[0] == launch.time_abilities[1] or not Catalog.fingerprint_valid(launch.projection_digest):
		return _failure(&"LAUNCH_MISMATCH")
	var validated = Envelope.validate_active_run_snapshot(run_snapshot, _catalog)
	if not validated.ok or validated.payload.is_empty() or not _run_matches_launch(validated.payload, launch):
		return _failure(&"RUN_INVALID")
	var run: Dictionary = validated.payload
	var projection: Variant = run.resources.get("meta_run_projection")
	if not projection is Dictionary or not MetaProjection.validate(projection, _catalog) or projection.projection_digest != launch.projection_digest or _remaining_soul(run.resources) < 0:
		return _failure(&"PROJECTION_INVALID")
	var receipts: Array = []
	for event: Variant in run.events:
		if event is Dictionary and event.get("type") == SOURCE_TYPE:
			receipts.append(event.get("receipt"))
	return _validate_sources(run, launch, receipts)


func verified_terminal_facts(launch: Dictionary, terminal: Dictionary) -> Dictionary:
	var verified := verified_run_sources(launch, terminal)
	if not verified.ok:
		return verified
	var normalized: Dictionary = Envelope.validate_active_run_snapshot(terminal, _catalog).payload
	var reason := str(normalized.result.get("result", ""))
	if not _terminal_matches_launch(normalized, launch, reason):
		return _failure(&"TERMINAL_INVALID")
	var boss_ids: Array = []
	for source: Dictionary in verified.context.sources:
		if source.kind == "boss":
			boss_ids.append(source.payload.boss_id)
	boss_ids.sort()
	return _success({"run_id": launch.run_id, "launch_sequence": int(launch.sequence), "terminal_reason": reason, "boss_ids": boss_ids})


func prepare(profile: Dictionary, launch: Dictionary, terminal: Dictionary, source_receipts: Array) -> Dictionary:
	var state = Profile.new()
	if _catalog == null or not state.configure(_catalog, profile):
		return _failure(&"PROFILE_INVALID")
	var before: Dictionary = state.snapshot()
	if launch.is_empty() or before.active_launch_receipt != launch:
		return _failure(&"LAUNCH_MISMATCH")
	var validated = Envelope.validate_active_run_snapshot(terminal, _catalog)
	if not validated.ok or validated.payload.is_empty():
		return _failure(&"TERMINAL_INVALID")
	var run: Dictionary = validated.payload
	var reason: String = str(run.result.get("result", ""))
	if not _terminal_matches_launch(run, launch, reason):
		return _failure(&"TERMINAL_INVALID")
	var projection_value: Variant = run.resources.get("meta_run_projection")
	if not projection_value is Dictionary or not MetaProjection.validate(projection_value, _catalog) or projection_value.projection_digest != launch.projection_digest:
		return _failure(&"PROJECTION_INVALID")
	var source_result := _validate_sources(run, launch, source_receipts)
	if not source_result.ok:
		return source_result
	var soul := _remaining_soul(run.resources)
	if soul < 0:
		return _failure(&"RESOURCE_INVALID")
	var earned := 3 if reason == "death" else 10
	for floor_id: String in run.completed_floor_ids:
		earned += 5 * (Envelope.FLOOR_IDS.find(floor_id) + 1)
	var imprints := 0
	var candidate := before.duplicate(true)
	for source: Dictionary in source_result.context.sources:
		if source.kind == "boss":
			earned += 15 + 5 * (Envelope.FLOOR_IDS.find(source.floor_id) + 1)
			if not candidate.completed_boss_ids.has(source.payload.boss_id):
				candidate.completed_boss_ids.append(source.payload.boss_id)
				imprints += 2
		else:
			earned += int(source.payload.chronos_shards)
			imprints += int(source.payload.existential_imprints)
		if earned > Catalog.MAX_VALUE or imprints > Catalog.MAX_VALUE:
			return _failure(&"CURRENCY_LIMIT")
	var doubled_multiplier: int = {"normal": 2, "hard": 3, "nightmare": 5}[launch.difficulty]
	var shards: int = (earned * doubled_multiplier) / 2
	var retention_percent := int(roundf(float(projection_value.soul_retention) * 100.0))
	var reserve: int = (soul * retention_percent) / 100
	if shards > Catalog.MAX_VALUE or before.chronos_shards > Catalog.MAX_VALUE - shards or before.existential_imprints > Catalog.MAX_VALUE - imprints:
		return _failure(&"CURRENCY_LIMIT")
	var receipt := {"schema_id": "meta_settlement_receipt_v1", "sequence": int(launch.sequence), "run_id": launch.run_id, "terminal_reason": reason, "shards": shards, "imprints": imprints, "soul_reserve": reserve}
	receipt["digest"] = JSON.stringify({"receipt": receipt, "projection_digest": launch.projection_digest, "sources": source_result.context.sources}, "", true, true).sha256_text()
	candidate.chronos_shards += shards
	candidate.existential_imprints += imprints
	candidate.soul_reserve = reserve
	candidate.completed_boss_ids.sort()
	candidate.active_launch_receipt = {}
	candidate.last_settlement_receipt = receipt.duplicate(true)
	candidate.statistics.finished_runs += 1
	candidate.statistics["deaths" if reason == "death" else "victories"] += 1
	candidate.revision += 1
	if not state.can_restore_snapshot(candidate):
		return _failure(&"PROFILE_LIMIT")
	return _success({"candidate": candidate, "receipt": receipt})


func import_legacy_statistics(profile: Dictionary, terminal: Dictionary, source_id: String) -> Dictionary:
	var state = Profile.new()
	if _catalog == null or not state.configure(_catalog, profile) or not Catalog.stable_id(source_id):
		return _failure(&"PROFILE_INVALID")
	var candidate: Dictionary = state.snapshot()
	var command_id := "legacy-stat:%s" % str(terminal.get("run_id", "")).sha256_text().substr(0, 40)
	if not Catalog.stable_id(command_id) or not candidate.active_launch_receipt.is_empty() or candidate.completed_command_ids.has(command_id):
		return _failure(&"SOURCE_INVALID")
	var validated = Envelope.validate_active_run_snapshot(terminal, _catalog)
	if not validated.ok or validated.payload.is_empty():
		return _failure(&"TERMINAL_INVALID")
	var run: Dictionary = validated.payload
	var reason: String = str(run.result.get("result", ""))
	if reason not in ["death", "victory", "abandon"] or not _matching_terminal_phase(run, reason):
		return _failure(&"TERMINAL_INVALID")
	candidate.statistics.finished_runs += 1
	var statistic: String = {"death": "deaths", "victory": "victories", "abandon": "abandons"}[reason]
	candidate.statistics[statistic] += 1
	candidate.completed_command_ids.append(command_id)
	candidate.completed_command_ids.sort()
	candidate.revision += 1
	if not state.can_restore_snapshot(candidate):
		return _failure(&"PROFILE_LIMIT")
	return _success({"candidate": candidate})


func prepare_abandon(profile: Dictionary, launch: Dictionary, active_run: Dictionary) -> Dictionary:
	var state = Profile.new()
	if _catalog == null or not state.configure(_catalog, profile):
		return _failure(&"PROFILE_INVALID")
	var before: Dictionary = state.snapshot()
	var validated = Envelope.validate_active_run_snapshot(active_run, _catalog)
	if launch.is_empty() or before.active_launch_receipt != launch or not validated.ok or validated.payload.is_empty():
		return _failure(&"LAUNCH_MISMATCH")
	var run: Dictionary = validated.payload
	if not _run_matches_launch(run, launch) or Phase.is_terminal(run.phase):
		return _failure(&"ACTIVE_RUN_INVALID")
	var candidate := before.duplicate(true)
	var receipt := {"schema_id": "meta_settlement_receipt_v1", "sequence": int(launch.sequence), "run_id": launch.run_id, "terminal_reason": "abandon", "shards": 0, "imprints": 0, "soul_reserve": 0}
	receipt["digest"] = JSON.stringify(receipt, "", true, true).sha256_text()
	candidate.active_launch_receipt = {}
	candidate.last_settlement_receipt = receipt.duplicate(true)
	candidate.soul_reserve = 0
	candidate.statistics.finished_runs += 1
	candidate.statistics.abandons += 1
	candidate.revision += 1
	if not state.can_restore_snapshot(candidate):
		return _failure(&"PROFILE_LIMIT")
	run.phase = Phase.Value.DEFEAT
	run.result = {"result": "abandon"}
	return _success({"candidate": candidate, "receipt": receipt, "terminal": run})


func _terminal_matches_launch(run: Dictionary, launch: Dictionary, reason: String) -> bool:
	if not _run_matches_launch(run, launch):
		return false
	if reason not in ["death", "victory"] or not _matching_terminal_phase(run, reason) or run.suspended or run.run_time_ms <= 0 or run.floor_plan.is_empty():
		return false
	return reason != "victory" or run.completed_floor_ids == Envelope.FLOOR_IDS


func _run_matches_launch(run: Dictionary, launch: Dictionary) -> bool:
	return run.run_id == launch.run_id and run.run_seed == launch.seed and run.config.get("difficulty") == launch.difficulty and run.config.get("milestone") in ["LAUNCH", "EXPANSION"] and run.config.get("character_id") == launch.character_id and run.config.get("weapon_id") == launch.weapon_id and run.config.get("enabled_time_skills") == launch.time_abilities


func _matching_terminal_phase(run: Dictionary, reason: String) -> bool:
	return run.phase == Phase.Value.VICTORY if reason == "victory" else run.phase == Phase.Value.DEFEAT


func _validate_sources(run: Dictionary, launch: Dictionary, receipts: Array) -> Dictionary:
	if receipts.size() > Profile.MAX_HISTORY:
		return _failure(&"SOURCE_LIMIT")
	var facts_result: Dictionary = Lifetime.validate_events(run.events)
	if not facts_result.ok:
		return _failure(&"ROOM_FACT_INVALID")
	var room_keys: Dictionary = {}
	for fact: Dictionary in facts_result.context.room_facts:
		room_keys["%s:%s" % [fact.floor_id, fact.node_id]] = true
	var material_room_keys := room_keys.duplicate()
	for node: Dictionary in run.floor_plan.nodes:
		if node.id == run.floor_plan.current_node_id and node.visited and node.room_type in ["combat", "elite", "boss"]:
			material_room_keys["%s:%s" % [run.floor_plan.floor_id, node.id]] = true
	var retained: Dictionary = {}
	for event: Variant in run.events:
		if event is Dictionary and event.get("type") == SOURCE_TYPE:
			if not Catalog.exact_fields(event, ["type", "receipt"]) or not _valid_source(event.receipt, launch, room_keys, material_room_keys) or retained.has(event.receipt.source_id):
				return _failure(&"SOURCE_INVALID")
			retained[event.receipt.source_id] = _normalize_source(event.receipt)
	if retained.size() != receipts.size():
		return _failure(&"SOURCE_MISMATCH")
	var sources: Dictionary = {}
	var boss_floors: Array = []
	var material_defeats: Array = []
	for value: Variant in receipts:
		if not _valid_source(value, launch, room_keys, material_room_keys) or sources.has(value.source_id) or not retained.has(value.source_id):
			return _failure(&"SOURCE_INVALID")
		var source := _normalize_source(value)
		if source != retained[value.source_id]:
			return _failure(&"SOURCE_MISMATCH")
		if source.kind == "boss":
			if boss_floors.has(source.floor_id) or not run.completed_floor_ids.has(source.floor_id):
				return _failure(&"BOSS_FACT_INVALID")
			boss_floors.append(source.floor_id)
		else:
			if material_defeats.has(source.payload.defeat_receipt):
				return _failure(&"MATERIAL_ALREADY_CLAIMED")
			material_defeats.append(source.payload.defeat_receipt)
		sources[source.source_id] = source
	boss_floors.sort()
	var completed: Array = run.completed_floor_ids.duplicate()
	completed.sort()
	if completed != boss_floors:
		return _failure(&"BOSS_FACT_MISSING")
	var ordered: Array = []
	var ids: Array = sources.keys()
	ids.sort()
	for id: String in ids:
		ordered.append(sources[id])
	return _success({"sources": ordered})


func _valid_source(value: Variant, launch: Dictionary, room_keys: Dictionary, material_room_keys: Dictionary) -> bool:
	if not Catalog.exact_fields(value, SOURCE_FIELDS) or value.schema_id != SOURCE_TYPE or not Catalog.stable_id(value.source_id) or value.run_id != launch.run_id or not Catalog.bounded_int(value.launch_sequence, 1, Catalog.MAX_VALUE) or value.launch_sequence != launch.sequence or value.floor_id not in Envelope.FLOOR_IDS or not value.node_id is String:
		return false
	if value.kind == "boss":
		return room_keys.has("%s:%s" % [value.floor_id, value.node_id]) and value.node_id == "boss" and Catalog.exact_fields(value.payload, ["actor_role", "boss_id"]) and value.payload.actor_role == "principal" and value.payload.boss_id == _boss_by_floor[value.floor_id] and value.source_id == source_id(value, value.payload.boss_id)
	if value.kind == "material":
		if not material_room_keys.has("%s:%s" % [value.floor_id, value.node_id]) or not Catalog.exact_fields(value.payload, ["actor_role", "principal_source_id", "defeat_receipt", "chronos_shards", "existential_imprints"]) or value.payload.actor_role != "principal" or not Catalog.stable_id(value.payload.principal_source_id):
			return false
		var defeat := "hostile_defeat:%s" % ("%s|%s" % [launch.run_id, value.payload.principal_source_id]).sha256_text().substr(0, 40)
		return value.payload.defeat_receipt == defeat and value.source_id == source_id(value, defeat) and Catalog.bounded_int(value.payload.chronos_shards, 0, 5) and Catalog.bounded_int(value.payload.existential_imprints, 0, 1) and (value.payload.chronos_shards > 0 or value.payload.existential_imprints > 0)
	return false


static func source_id(value: Dictionary, native_identity: String) -> String:
	return "meta_%s:%s" % [value.kind, ("%s|%d|%s|%s|%s" % [value.run_id, int(value.launch_sequence), value.floor_id, value.node_id, native_identity]).sha256_text().substr(0, 40)]


func _normalize_source(value: Dictionary) -> Dictionary:
	var normalized := value.duplicate(true)
	normalized.launch_sequence = int(value.launch_sequence)
	if value.kind == "material":
		normalized.payload.chronos_shards = int(value.payload.chronos_shards)
		normalized.payload.existential_imprints = int(value.payload.existential_imprints)
	return normalized


func _remaining_soul(resources: Dictionary) -> int:
	if not resources.has("resource"):
		return 0
	var authority = Resources.new()
	if not resources.resource is Dictionary or not resources.resource.get("resources") is Dictionary or not authority.configure(resources.resource.resources) or not authority.restore_snapshot(resources.resource):
		return -1
	return int(authority.snapshot().resources.get("soul_energy", 0))


func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}


func _success(context: Dictionary) -> Dictionary:
	return {"ok": true, "code": &"OK", "context": context.duplicate(true)}
