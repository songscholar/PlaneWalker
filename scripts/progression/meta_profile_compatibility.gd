class_name MetaProfileCompatibility
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const MetaProjection := preload("res://scripts/progression/meta_run_projection.gd")
const Phase := preload("res://scripts/application/run_phase.gd")
const MIRROR_FIELDS := ["chronos_shards", "existential_imprints", "unlocked_nodes", "discovered_items", "unlocked_characters", "unlocked_weapons", "weapon_proficiency", "npc_affinity", "unlocked_achievements", "cosmetics"]
const LEGACY_NODE_IDS := {"node_guard_1": "W-01"}


static func from_legacy(payload: Dictionary, catalog: RefCounted) -> Dictionary:
	var state = Profile.new()
	if not state.configure(catalog):
		return _failure(&"CATALOG_INVALID")
	if payload.has("meta_profile_state"):
		if not payload.meta_profile_state is Dictionary or not state.restore_snapshot(payload.meta_profile_state) or not mirrors_match(payload, state.snapshot()):
			return _failure(&"PROFILE_INVALID")
		return _success(_with_mirrors(payload, state.snapshot()))
	var profile: Dictionary = state.snapshot()
	for field: String in MIRROR_FIELDS:
		if not payload.has(field):
			continue
		var value: Variant = payload[field]
		if field in ["weapon_proficiency", "npc_affinity"]:
			if not value is Dictionary:
				return _failure(&"LEGACY_FIELD_INVALID")
			for id: Variant in value:
				if not profile[field].has(id):
					return _failure(&"LEGACY_ID_UNKNOWN")
				profile[field][id] = value[id]
		elif field == "unlocked_nodes":
			if not value is Array:
				return _failure(&"LEGACY_FIELD_INVALID")
			var nodes: Array = []
			for id: Variant in value:
				var mapped: Variant = LEGACY_NODE_IDS.get(id, id)
				if not mapped is String or catalog.call("definition", StringName(mapped)).is_empty() or nodes.has(mapped):
					return _failure(&"LEGACY_ID_UNKNOWN")
				nodes.append(mapped)
			nodes.sort()
			profile[field] = nodes
		elif field == "cosmetics" and value is Dictionary:
			var owned: Array = []
			for character: Variant in value:
				if character not in Catalog.CHARACTER_IDS or not value[character] is Array:
					return _failure(&"LEGACY_ID_UNKNOWN")
				for cosmetic: Variant in value[character]:
					var id := "%s.%s" % [character, str(cosmetic)]
					if not catalog.call("has_reference", "cosmetic", id) or owned.has(id):
						return _failure(&"LEGACY_ID_UNKNOWN")
					owned.append(id)
			owned.sort()
			profile[field] = owned
		else:
			profile[field] = value.duplicate(true) if value is Dictionary or value is Array else value
	for pair: Array in [["unlocked_characters", ["wanderer"]], ["unlocked_weapons", ["bow", "sword"]]]:
		if not profile[pair[0]] is Array:
			return _failure(&"LEGACY_FIELD_INVALID")
		for id: String in pair[1]:
			if not profile[pair[0]].has(id):
				profile[pair[0]].append(id)
		profile[pair[0]].sort()
	for pair: Array in [["runs_completed", "finished_runs"], ["victories", "victories"], ["deaths", "deaths"], ["abandons", "abandons"]]:
		if payload.has(pair[0]):
			profile.statistics[pair[1]] = payload[pair[0]]
	if not state.restore_snapshot(profile):
		return _failure(&"LEGACY_PROFILE_INVALID")
	var normalized := _with_mirrors(payload, state.snapshot())
	if normalized.get("active_run_state") is Dictionary and not normalized.active_run_state.is_empty():
		if not normalized.active_run_state.get("resources") is Dictionary:
			return _failure(&"LEGACY_ACTIVE_RUN_INVALID")
		if normalized.active_run_state.resources.has("meta_run_projection"):
			return _failure(&"UNDECLARED_META_PROJECTION")
		# Old in-flight runs cannot inherit later purchases or forging effects.
		var fresh = Profile.new()
		fresh.configure(catalog)
		normalized.active_run_state.resources["meta_run_projection"] = MetaProjection.from_profile(fresh.snapshot(), catalog).context.projection
	return _success(normalized)


static func mirrors_match(payload: Dictionary, profile: Dictionary) -> bool:
	for field: String in MIRROR_FIELDS:
		if payload.has(field) and not _json_equal(payload[field], profile[field]):
			return false
	return true


static func run_matches_profile(run: Dictionary, profile: Dictionary, catalog: RefCounted) -> bool:
	if run.is_empty():
		return true
	var projection: Variant = run.get("resources", {}).get("meta_run_projection")
	if not projection is Dictionary or not MetaProjection.validate(projection, catalog):
		return false
	var launch: Dictionary = profile.active_launch_receipt
	if not launch.is_empty():
		var config: Dictionary = run.config
		return run.run_id == launch.run_id and run.run_seed == launch.seed and config.get("difficulty") == launch.difficulty and config.get("character_id") == launch.character_id and config.get("weapon_id") == launch.weapon_id and config.get("enabled_time_skills") == launch.time_abilities and projection.projection_digest == launch.projection_digest
	var settlement: Dictionary = profile.last_settlement_receipt
	if not settlement.is_empty() and settlement.run_id == run.run_id:
		return run.result.get("result") == settlement.terminal_reason and run.phase == (Phase.Value.VICTORY if settlement.terminal_reason == "victory" else Phase.Value.DEFEAT)
	var fresh = Profile.new()
	if not fresh.configure(catalog):
		return false
	return projection.projection_digest == MetaProjection.from_profile(fresh.snapshot(), catalog).context.projection.projection_digest


static func _with_mirrors(payload: Dictionary, profile: Dictionary) -> Dictionary:
	var normalized := payload.duplicate(true)
	normalized["meta_profile_state"] = profile.duplicate(true)
	for field: String in MIRROR_FIELDS:
		normalized[field] = profile[field].duplicate(true) if profile[field] is Dictionary or profile[field] is Array else profile[field]
	return normalized


static func _json_equal(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left, "", true, true)) == JSON.parse_string(JSON.stringify(right, "", true, true))


static func _success(payload: Dictionary) -> Dictionary:
	return {"ok": true, "code": &"OK", "context": {"payload": payload}}


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
