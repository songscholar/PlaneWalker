class_name WeaponProficiencyRuntime
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Forge := preload("res://scripts/progression/forge_runtime.gd")
const Candidate := preload("res://scripts/progression/profile_command_candidate.gd")
const SCHEMA_ID := "planewalker.weapon_proficiency"
const SCHEMA_VERSION := 1
const ROOT_FIELDS := ["schema_id", "schema_version", "revision", "experience", "high_water"]
const CONTEXT_IDS := ["normal_run", "training_drill"]
const ACTION_IDS := ["weapon_primary", "weapon_secondary", "weapon_utility", "weapon_skill", "weapon_ultimate"]
const RECEIPT_FIELDS := ["session_sequence", "action_sequence", "weapon_id", "action_id", "context_id"]
const TICKET_FIELDS := ["ticket_id", "owner_id", "base_revision", "candidate_digest"]

var _forge: RefCounted
var _state: Dictionary = {}
var _prepared: Dictionary = {}
var _ticket_sequence := 0


func configure(entries: Array, catalog: RefCounted, value: Dictionary = {}) -> Dictionary:
	_forge = null
	_state.clear()
	_prepared.clear()
	var forge := Forge.new()
	var configured := forge.configure(entries, catalog)
	if not configured.ok:
		return configured
	var candidate := _normalize(value if not value.is_empty() else _fresh())
	if candidate.is_empty():
		return Candidate.failure(&"PROFICIENCY_STATE_INVALID")
	_forge = forge
	_state = candidate
	return Candidate.success()


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func restore_snapshot(value: Dictionary) -> bool:
	if _forge == null:
		return false
	var candidate := _normalize(value)
	if candidate.is_empty():
		return false
	_state = candidate
	_prepared.clear()
	return true


func prepare_observation(receipt: Dictionary, expected_revision: int) -> Dictionary:
	# The native adapter authenticates session/action counters before calling this domain.
	if _forge == null:
		return Candidate.failure(&"NOT_CONFIGURED")
	if expected_revision != _state.revision:
		return Candidate.failure(&"STALE_REVISION")
	if not Catalog.exact_fields(receipt, RECEIPT_FIELDS) or not receipt.weapon_id is String or receipt.weapon_id not in Catalog.WEAPON_IDS or not receipt.context_id is String or receipt.context_id not in CONTEXT_IDS or not receipt.action_id is String or receipt.action_id not in ACTION_IDS or not Catalog.bounded_int(receipt.session_sequence, 1, Catalog.MAX_VALUE) or not Catalog.bounded_int(receipt.action_sequence, 1, Catalog.MAX_VALUE):
		return Candidate.failure(&"OBSERVATION_INVALID")
	var high_water: Dictionary = _state.high_water[receipt.weapon_id][receipt.context_id]
	if receipt.session_sequence < high_water.session_sequence or receipt.session_sequence == high_water.session_sequence and receipt.action_sequence <= high_water.action_sequence:
		return Candidate.failure(&"OBSERVATION_RETIRED")
	if receipt.session_sequence > high_water.session_sequence and receipt.action_sequence != 1:
		return Candidate.failure(&"SESSION_START_INVALID")
	if _state.experience[receipt.weapon_id] == Catalog.MAX_VALUE or _state.revision == Catalog.MAX_VALUE or _ticket_sequence == Catalog.MAX_VALUE or _prepared.size() >= 32:
		return Candidate.failure(&"TRANSACTION_LIMIT")
	var candidate := snapshot()
	candidate.experience[receipt.weapon_id] += 1
	candidate.revision += 1
	candidate.high_water[receipt.weapon_id][receipt.context_id] = {"session_sequence": int(receipt.session_sequence), "action_sequence": int(receipt.action_sequence)}
	_ticket_sequence += 1
	var ticket := {"ticket_id": _ticket_sequence, "owner_id": get_instance_id(), "base_revision": _state.revision, "candidate_digest": JSON.stringify(candidate, "", true, true).sha256_text()}
	_prepared[_ticket_sequence] = {"before": snapshot(), "candidate": candidate, "ticket": ticket.duplicate(true)}
	return Candidate.success({"ticket": ticket.duplicate(true)})


func candidate_snapshot(ticket: Dictionary) -> Dictionary:
	if not _ticket_valid(ticket):
		return {}
	return (_prepared[ticket.ticket_id].candidate as Dictionary).duplicate(true)


func commit_candidate(ticket: Dictionary) -> Dictionary:
	if not _ticket_valid(ticket):
		return Candidate.failure(&"TICKET_INVALID")
	_state = (_prepared[ticket.ticket_id].candidate as Dictionary).duplicate(true)
	_prepared.clear()
	return Candidate.success({"snapshot": snapshot()})


func discard_candidate(ticket: Dictionary) -> bool:
	if not _ticket_valid(ticket):
		return false
	_prepared.erase(ticket.ticket_id)
	return true


func project(weapon_id: String) -> Dictionary:
	if _forge == null or not _state.experience.has(weapon_id):
		return {}
	var definition: Dictionary = _forge.call("weapon_definition", weapon_id)
	var thresholds: Array = definition.proficiency_thresholds
	var experience: int = _state.experience[weapon_id]
	var level := 1
	for index: int in range(thresholds.size()):
		if experience >= thresholds[index]:
			level = index + 1
	return {"weapon_id": weapon_id, "experience": experience, "level": level, "next_threshold": int(thresholds[level]) if level < thresholds.size() else 0, "attack_bonus": 0.0, "drill_tier": level, "preview_detail_tier": level, "cosmetic_tier": level}


func _ticket_valid(ticket: Dictionary) -> bool:
	return Catalog.exact_fields(ticket, TICKET_FIELDS) and Catalog.bounded_int(ticket.ticket_id, 1, Catalog.MAX_VALUE) and _prepared.has(ticket.ticket_id) and _prepared[ticket.ticket_id].ticket == ticket and _prepared[ticket.ticket_id].before == _state


func _fresh() -> Dictionary:
	var experience: Dictionary = {}
	var high_water: Dictionary = {}
	for weapon_id: String in Catalog.WEAPON_IDS:
		experience[weapon_id] = 0
		high_water[weapon_id] = {}
		for context_id: String in CONTEXT_IDS:
			high_water[weapon_id][context_id] = {"session_sequence": 0, "action_sequence": 0}
	return {"schema_id": SCHEMA_ID, "schema_version": SCHEMA_VERSION, "revision": 0, "experience": experience, "high_water": high_water}


func _normalize(value: Dictionary) -> Dictionary:
	if not Catalog.exact_fields(value, ROOT_FIELDS) or value.schema_id != SCHEMA_ID or not Catalog.bounded_int(value.schema_version, SCHEMA_VERSION, SCHEMA_VERSION) or not Catalog.bounded_int(value.revision, 0, Catalog.MAX_VALUE) or not Catalog.exact_fields(value.experience, Catalog.WEAPON_IDS) or not Catalog.exact_fields(value.high_water, Catalog.WEAPON_IDS):
		return {}
	var normalized := value.duplicate(true)
	normalized.schema_version = SCHEMA_VERSION
	normalized.revision = int(value.revision)
	for weapon_id: String in Catalog.WEAPON_IDS:
		if not Catalog.bounded_int(value.experience[weapon_id], 0, Catalog.MAX_VALUE) or not Catalog.exact_fields(value.high_water[weapon_id], CONTEXT_IDS):
			return {}
		normalized.experience[weapon_id] = int(value.experience[weapon_id])
		for context_id: String in CONTEXT_IDS:
			var mark: Variant = value.high_water[weapon_id][context_id]
			if not Catalog.exact_fields(mark, ["session_sequence", "action_sequence"]) or not Catalog.bounded_int(mark.session_sequence, 0, Catalog.MAX_VALUE) or not Catalog.bounded_int(mark.action_sequence, 0, Catalog.MAX_VALUE) or (mark.session_sequence == 0) != (mark.action_sequence == 0):
				return {}
			normalized.high_water[weapon_id][context_id] = {"session_sequence": int(mark.session_sequence), "action_sequence": int(mark.action_sequence)}
	return normalized
