class_name MetaProfileState
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const SCHEMA_ID := "planewalker.meta_profile_state"
const SCHEMA_VERSION := 1
const ROOT_FIELDS := ["schema_id", "schema_version", "catalog_fingerprint", "revision", "chronos_shards", "existential_imprints", "unlocked_nodes", "discovered_items", "unlocked_characters", "unlocked_weapons", "weapon_proficiency", "forge_state", "npc_affinity", "faction_standing", "narrative_state", "tutorial_state", "build_library", "repair_stage", "launch_sequence", "active_launch_receipt", "last_settlement_receipt", "completed_command_ids", "completed_boss_ids", "unlocked_achievements", "cosmetics", "soul_reserve", "statistics"]
const NARRATIVE_FIELDS := ["flags", "artifacts", "environment_records", "hidden_steps", "nemesis_choices", "vera_conversations", "heart_fragments", "endings", "credits_completed", "void_exposure_frames", "consumed_sources", "balance_choice_sources"]
const TUTORIAL_FIELDS := ["completed_lessons", "skipped_lessons", "seen_hints", "suppressed", "guided_runs_completed"]
const STATISTIC_FIELDS := ["finished_runs", "victories", "deaths", "abandons"]
const MAX_HISTORY := 4096
const RESERVED_COMMAND_PREFIXES := ["forge-enchant-unlock:", "legacy-stat:", "training-claim:", "narrative-source:", "onboarding-progress:", "onboarding-watermark:"]

var _catalog: RefCounted
var _state: Dictionary = {}
var _prepared: Dictionary = {}
var _ticket_sequence := 0


func configure(catalog: RefCounted, value: Dictionary = {}) -> bool:
	if catalog == null or not catalog.has_method("fingerprint") or not Catalog.fingerprint_valid(catalog.call("fingerprint")):
		return false
	for method: String in ["ids", "definition", "has_reference"]:
		if not catalog.has_method(method):
			return false
	var previous := _catalog
	_catalog = catalog
	var candidate := _normalize_snapshot(value if not value.is_empty() else _fresh_profile())
	if candidate.is_empty():
		_catalog = previous
		return false
	_state = candidate
	_prepared.clear()
	return true


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func can_restore_snapshot(value: Dictionary) -> bool:
	return _catalog != null and not _normalize_snapshot(value).is_empty()


func restore_snapshot(value: Dictionary) -> bool:
	if _catalog == null:
		return false
	var normalized := _normalize_snapshot(value)
	if normalized.is_empty():
		return false
	_state = normalized
	_prepared.clear()
	return true


func prepare_command(command: Dictionary, expected_revision: int) -> Dictionary:
	if _state.is_empty() or _state.catalog_fingerprint != _catalog.call("fingerprint"):
		return _failure(&"NOT_CONFIGURED")
	if expected_revision != _state.revision:
		return _failure(&"STALE_REVISION", {"revision": _state.revision})
	if not Catalog.exact_fields(command, ["command_id", "kind", "node_id"]) or command.kind != "meta_unlock" or not Catalog.stable_id(command.command_id) or not command.node_id is String:
		return _failure(&"COMMAND_INVALID")
	for prefix: String in RESERVED_COMMAND_PREFIXES:
		if command.command_id.begins_with(prefix):
			return _failure(&"COMMAND_INVALID")
	if _state.completed_command_ids.has(command.command_id):
		return _failure(&"DUPLICATE_COMMAND")
	if _state.completed_command_ids.size() >= MAX_HISTORY or _state.revision == Catalog.MAX_VALUE or _prepared.size() >= 32:
		return _failure(&"TRANSACTION_LIMIT")
	var definition: Dictionary = _catalog.call("definition", StringName(command.node_id))
	if definition.is_empty():
		return _failure(&"NODE_UNKNOWN")
	if _state.unlocked_nodes.has(command.node_id):
		return _failure(&"ALREADY_UNLOCKED")
	for prerequisite: String in definition.prerequisites:
		if not _state.unlocked_nodes.has(prerequisite):
			return _failure(&"PREREQUISITE_MISSING", {"node_id": prerequisite})
	for currency: String in ["chronos_shards", "existential_imprints"]:
		if _state[currency] < definition.cost[currency]:
			return _failure(&"INSUFFICIENT_CURRENCY", {"currency": currency, "required": definition.cost[currency]})
	var candidate := snapshot()
	for currency: String in ["chronos_shards", "existential_imprints"]:
		candidate[currency] -= definition.cost[currency]
	candidate.unlocked_nodes.append(command.node_id)
	candidate.unlocked_nodes.sort()
	candidate.completed_command_ids.append(command.command_id)
	candidate.completed_command_ids.sort()
	candidate.revision += 1
	return prepare_candidate(candidate)


func prepare_candidate(candidate: Dictionary) -> Dictionary:
	if _state.is_empty() or _prepared.size() >= 32 or _state.revision == Catalog.MAX_VALUE or _ticket_sequence == Catalog.MAX_VALUE:
		return _failure(&"TRANSACTION_LIMIT")
	var normalized := _normalize_snapshot(candidate)
	if normalized.is_empty() or normalized.revision != _state.revision + 1:
		return _failure(&"CANDIDATE_INVALID")
	_ticket_sequence += 1
	var ticket := {"ticket_id": _ticket_sequence, "owner_id": get_instance_id(), "base_revision": _state.revision, "candidate_digest": JSON.stringify(normalized, "", true, true).sha256_text()}
	_prepared[_ticket_sequence] = {"ticket": ticket.duplicate(true), "before": snapshot(), "candidate": normalized}
	return _success({"ticket": ticket.duplicate(true)})


func candidate_snapshot(ticket: Dictionary) -> Dictionary:
	if not _valid_ticket(ticket):
		return {}
	return (_prepared[ticket.ticket_id].candidate as Dictionary).duplicate(true)


func commit_candidate(ticket: Dictionary) -> Dictionary:
	if not _valid_ticket(ticket):
		return _failure(&"TICKET_INVALID")
	_state = (_prepared[ticket.ticket_id].candidate as Dictionary).duplicate(true)
	_prepared.clear()
	return _success({"snapshot": snapshot()})


func discard_candidate(ticket: Dictionary) -> bool:
	if not _valid_ticket(ticket):
		return false
	_prepared.erase(ticket.ticket_id)
	return true


func _valid_ticket(ticket: Dictionary) -> bool:
	return Catalog.exact_fields(ticket, ["ticket_id", "owner_id", "base_revision", "candidate_digest"]) and Catalog.bounded_int(ticket.ticket_id, 1, Catalog.MAX_VALUE) and _prepared.has(ticket.ticket_id) and _prepared[ticket.ticket_id].ticket == ticket and _prepared[ticket.ticket_id].before == _state and _state.catalog_fingerprint == _catalog.call("fingerprint")


func _fresh_profile() -> Dictionary:
	var proficiency: Dictionary = {}
	var forging: Dictionary = {}
	var affinity: Dictionary = {}
	var factions: Dictionary = {}
	var hidden: Dictionary = {}
	for id: String in Catalog.WEAPON_IDS:
		proficiency[id] = 0
		forging[id] = {"level": 0, "enchant_preferences": [], "void_tempered": false}
	for id: String in Catalog.NPC_IDS:
		affinity[id] = 0
	for id: String in Catalog.FACTION_IDS:
		factions[id] = 0
	for id: String in Catalog.HIDDEN_LINE_IDS:
		hidden[id] = 0
	return {
		"schema_id": SCHEMA_ID, "schema_version": SCHEMA_VERSION, "catalog_fingerprint": _catalog.call("fingerprint"), "revision": 0,
		"chronos_shards": 0, "existential_imprints": 0, "unlocked_nodes": [], "discovered_items": [], "unlocked_characters": ["wanderer"], "unlocked_weapons": ["bow", "sword"],
		"weapon_proficiency": proficiency, "forge_state": forging, "npc_affinity": affinity, "faction_standing": factions,
		"narrative_state": {"flags": [], "artifacts": [], "environment_records": [], "hidden_steps": hidden, "nemesis_choices": [], "vera_conversations": 0, "heart_fragments": [], "endings": [], "credits_completed": [], "void_exposure_frames": 0, "consumed_sources": [], "balance_choice_sources": []},
		"tutorial_state": {"completed_lessons": [], "skipped_lessons": [], "seen_hints": [], "suppressed": false, "guided_runs_completed": 0},
		"build_library": [], "repair_stage": 0, "launch_sequence": 0, "active_launch_receipt": {}, "last_settlement_receipt": {}, "completed_command_ids": [], "completed_boss_ids": [], "unlocked_achievements": [], "cosmetics": [], "soul_reserve": 0,
		"statistics": {"finished_runs": 0, "victories": 0, "deaths": 0, "abandons": 0},
	}


func _normalize_snapshot(value: Dictionary) -> Dictionary:
	if not Catalog.exact_fields(value, ROOT_FIELDS) or value.schema_id != SCHEMA_ID or not Catalog.bounded_int(value.schema_version, 1, 1) or value.catalog_fingerprint != _catalog.call("fingerprint"):
		return {}
	for field: String in ["revision", "chronos_shards", "existential_imprints", "launch_sequence", "soul_reserve"]:
		if not Catalog.bounded_int(value[field], 0, Catalog.MAX_VALUE):
			return {}
	if not Catalog.bounded_int(value.repair_stage, 0, 3) or not _ids(value.unlocked_nodes, _catalog.call("ids")) or not _ids(value.unlocked_characters, Catalog.CHARACTER_IDS) or not value.unlocked_characters.has("wanderer") or not _ids(value.unlocked_weapons, Catalog.WEAPON_IDS) or not value.unlocked_weapons.has("sword") or not value.unlocked_weapons.has("bow"):
		return {}
	for id: String in value.unlocked_nodes:
		var definition: Dictionary = _catalog.call("definition", StringName(id))
		for prerequisite: String in definition.prerequisites:
			if not value.unlocked_nodes.has(prerequisite):
				return {}
	for pair: Array in [["discovered_items", "item"], ["unlocked_achievements", "achievement"], ["cosmetics", "cosmetic"]]:
		if not _reference_ids(value[pair[0]], pair[1]):
			return {}
	if not _ids(value.completed_boss_ids, Catalog.BOSS_IDS) or not _source_ids(value.completed_command_ids) or not _int_map(value.weapon_proficiency, Catalog.WEAPON_IDS, 0, Catalog.MAX_VALUE) or not _int_map(value.npc_affinity, Catalog.NPC_IDS, 0, 100) or not _int_map(value.faction_standing, Catalog.FACTION_IDS, -100, 100):
		return {}
	if not _valid_forge(value.forge_state, value.unlocked_nodes) or not _valid_narrative(value.narrative_state) or not _valid_tutorial(value.tutorial_state) or not _valid_builds(value.build_library) or not _int_map(value.statistics, STATISTIC_FIELDS, 0, Catalog.MAX_VALUE) or int(value.statistics.victories) + int(value.statistics.deaths) + int(value.statistics.abandons) > int(value.statistics.finished_runs):
		return {}
	if not _valid_launch(value.active_launch_receipt, value) or not _valid_settlement(value.last_settlement_receipt, value):
		return {}
	return _normalize_integer_values(value)


func _valid_forge(value: Variant, unlocked: Array) -> bool:
	if not Catalog.exact_fields(value, Catalog.WEAPON_IDS):
		return false
	for id: String in Catalog.WEAPON_IDS:
		var state: Variant = value[id]
		if not Catalog.exact_fields(state, ["level", "enchant_preferences", "void_tempered"]) or not Catalog.bounded_int(state.level, 0, 5) or not state.void_tempered is bool or not _reference_ids(state.enchant_preferences, "enchantment") or state.enchant_preferences.size() > 2:
			return false
		if state.level > 0 and not unlocked.has("F-01") or state.void_tempered and not unlocked.has("F-04") or state.enchant_preferences.size() >= 1 and not unlocked.has("F-02") or state.enchant_preferences.size() == 2 and not unlocked.has("F-03"):
			return false
		for group: Array in [["EN-01", "EN-02", "EN-03"], ["EN-04", "EN-05"]]:
			var equipped := 0
			for enchantment: String in state.enchant_preferences:
				if group.has(enchantment):
					equipped += 1
			if equipped > 1:
				return false
	return true


func _valid_narrative(value: Variant) -> bool:
	if not Catalog.exact_fields(value, NARRATIVE_FIELDS) or not _int_map(value.hidden_steps, Catalog.HIDDEN_LINE_IDS, 0, 5):
		return false
	for pair: Array in [["flags", "narrative_flag"], ["artifacts", "artifact"], ["environment_records", "environment_record"], ["endings", "ending"], ["credits_completed", "ending"]]:
		if not _reference_ids(value[pair[0]], pair[1]):
			return false
	for ending: String in value.credits_completed:
		if not value.endings.has(ending):
			return false
	if not _ids(value.heart_fragments, Catalog.FLOOR_IDS) or not Catalog.bounded_int(value.vera_conversations, 0, 5) or not Catalog.bounded_int(value.void_exposure_frames, 0, Catalog.MAX_VALUE) or not _source_ids(value.consumed_sources) or not _source_ids(value.balance_choice_sources):
		return false
	for source: String in value.balance_choice_sources:
		if not value.consumed_sources.has(source):
			return false
	if not value.nemesis_choices is Array or value.nemesis_choices.size() > 5:
		return false
	for choice: Variant in value.nemesis_choices:
		if choice not in ["spare", "attack"]:
			return false
	return true


func _valid_tutorial(value: Variant) -> bool:
	if not Catalog.exact_fields(value, TUTORIAL_FIELDS) or not value.suppressed is bool or not Catalog.bounded_int(value.guided_runs_completed, 0, 3):
		return false
	return _reference_ids(value.completed_lessons, "tutorial_lesson") and _reference_ids(value.skipped_lessons, "tutorial_lesson") and _reference_ids(value.seen_hints, "tutorial_hint")


func _valid_builds(value: Variant) -> bool:
	if not value is Array or value.size() > 32:
		return false
	var seen: Array = []
	for build: Variant in value:
		if not Catalog.exact_fields(build, ["id", "name", "character_id", "weapon_id", "time_abilities"]) or not Catalog.stable_id(build.id) or seen.has(build.id) or not build.name is String or build.name.is_empty() or build.name.length() > 64 or build.name.to_utf8_buffer().has(0) or build.character_id not in Catalog.CHARACTER_IDS or build.weapon_id not in Catalog.WEAPON_IDS or not _valid_time_pair(build.time_abilities):
			return false
		seen.append(build.id)
	return true


func _valid_launch(value: Variant, profile: Dictionary) -> bool:
	if not value is Dictionary:
		return false
	if value.is_empty():
		return true
	return Catalog.exact_fields(value, ["schema_id", "sequence", "run_id", "difficulty", "seed", "character_id", "weapon_id", "time_abilities", "projection_digest"]) and value.schema_id == "meta_launch_receipt_v1" and Catalog.bounded_int(value.sequence, 1, Catalog.MAX_VALUE) and value.sequence == profile.launch_sequence and Catalog.stable_id(value.run_id) and value.difficulty in ["normal", "hard", "nightmare"] and Catalog.bounded_int(value.seed, 0, Catalog.MAX_VALUE) and profile.unlocked_characters.has(value.character_id) and profile.unlocked_weapons.has(value.weapon_id) and _valid_time_pair(value.time_abilities) and Catalog.fingerprint_valid(value.projection_digest)


func _valid_settlement(value: Variant, profile: Dictionary) -> bool:
	if not value is Dictionary:
		return false
	if value.is_empty():
		return true
	if not Catalog.exact_fields(value, ["schema_id", "sequence", "run_id", "terminal_reason", "shards", "imprints", "soul_reserve", "digest"]) or value.schema_id != "meta_settlement_receipt_v1" or not Catalog.bounded_int(value.sequence, 1, int(profile.launch_sequence)) or not Catalog.stable_id(value.run_id) or value.terminal_reason not in ["death", "victory", "abandon"] or not Catalog.fingerprint_valid(value.digest):
		return false
	for field: String in ["shards", "imprints", "soul_reserve"]:
		if not Catalog.bounded_int(value[field], 0, Catalog.MAX_VALUE):
			return false
	return profile.active_launch_receipt.is_empty() or value.sequence < profile.active_launch_receipt.sequence


func _valid_time_pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and value[0] in Catalog.TIME_IDS and value[1] in Catalog.TIME_IDS and value[0] != value[1]


func _int_map(value: Variant, fields: Array, minimum: int, maximum: int) -> bool:
	if not Catalog.exact_fields(value, fields):
		return false
	for field: String in fields:
		if not Catalog.bounded_int(value[field], minimum, maximum):
			return false
	return true


func _ids(value: Variant, allowed: Array) -> bool:
	if not _source_ids(value):
		return false
	for id: String in value:
		if not allowed.has(id):
			return false
	return true


func _reference_ids(value: Variant, category: String) -> bool:
	if not _source_ids(value):
		return false
	for id: String in value:
		if not bool(_catalog.call("has_reference", category, id)):
			return false
	return true


func _source_ids(value: Variant) -> bool:
	if not value is Array or value.size() > MAX_HISTORY:
		return false
	var previous := ""
	for id: Variant in value:
		if not Catalog.stable_id(id) or not previous.is_empty() and previous >= str(id):
			return false
		previous = id
	return true


func _normalize_integer_values(value: Variant) -> Variant:
	if value is Dictionary:
		var normalized: Dictionary = {}
		for key: Variant in value:
			normalized[key] = _normalize_integer_values(value[key])
		return normalized
	if value is Array:
		var normalized: Array = []
		for child: Variant in value:
			normalized.append(_normalize_integer_values(child))
		return normalized
	return int(value) if value is float else value


static func _success(context: Dictionary = {}) -> Dictionary:
	return {"ok": true, "code": &"OK", "context": context}


static func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context}
