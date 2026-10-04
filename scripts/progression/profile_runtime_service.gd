class_name ProfileRuntimeService
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const MetaProjection := preload("res://scripts/progression/meta_run_projection.gd")
const Settlement := preload("res://scripts/progression/run_settlement_authority.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const Paths := preload("res://scripts/save/save_path_policy.gd")
const Forge := preload("res://scripts/progression/forge_runtime.gd")
const Builds := preload("res://scripts/progression/build_library.gd")
const MIRROR_FIELDS := ["chronos_shards", "existential_imprints", "unlocked_nodes", "discovered_items", "unlocked_characters", "unlocked_weapons", "weapon_proficiency", "npc_affinity", "unlocked_achievements", "cosmetics"]
const BOSS_ORDER := ["ruin_king", "forest_heart", "time_sovereign", "forge_colossus", "void_throne"]

var _catalog: RefCounted
var _profile: RefCounted
var _settlement: RefCounted
var _save: RefCounted
var _profile_id := ""
var _save_domain := ""
var _payload: Dictionary = {}
var _busy := false
var _forge: RefCounted
var _builds: RefCounted


func configure(catalog: RefCounted, save_service: RefCounted, profile_id: String, save_domain: String, initial_payload: Dictionary = {}) -> Dictionary:
	if _busy or save_service == null or not save_service.has_method("save_profile") or not save_service.has_method("load_profile") or not save_service.has_method("inspect_profile") or not Paths.validate_id(profile_id).ok or not Paths.validate_id(save_domain).ok:
		return _failure(&"CONFIGURATION_INVALID")
	if not save_service.has_method("enable_meta_profile") or not save_service.call("enable_meta_profile", catalog).ok:
		return _failure(&"CONFIGURATION_INVALID")
	var loaded = save_service.call("load_profile", profile_id, save_domain)
	if not loaded.ok and loaded.code != &"NOT_FOUND":
		return _failure(loaded.code)
	var payload_value: Dictionary = loaded.payload if loaded.ok else initial_payload
	var state = Profile.new()
	var nested: Variant = payload_value.get("meta_profile_state", {})
	if not nested is Dictionary or not state.configure(catalog, nested) or loaded.ok and nested.is_empty():
		return _failure(&"PROFILE_INVALID")
	if not _mirrors_match(payload_value, state.snapshot()):
		return _failure(&"PROFILE_MIRROR_MISMATCH")
	var settlement = Settlement.new()
	var bosses: Dictionary = {}
	for index: int in range(5):
		bosses[Envelope.FLOOR_IDS[index]] = BOSS_ORDER[index]
	if not settlement.configure(catalog, bosses):
		return _failure(&"CONFIGURATION_INVALID")
	_catalog = catalog
	_profile = state
	_settlement = settlement
	_save = save_service
	_profile_id = profile_id
	_save_domain = save_domain
	_payload = payload_value.duplicate(true)
	_forge = null
	_builds = null
	return _success({"snapshot": snapshot()})


func snapshot() -> Dictionary:
	return _profile.call("snapshot") if _profile != null else {}


func payload() -> Dictionary:
	return _payload.duplicate(true)


func enable_workshop(entries: Array) -> Dictionary:
	if _profile == null or _busy:
		return _failure(&"NOT_CONFIGURED")
	var forge = Forge.new()
	var configured: Dictionary = forge.configure(entries, _catalog)
	var builds = Builds.new()
	if not configured.ok or not builds.configure(_catalog):
		return _failure(&"WORKSHOP_CONTENT_INVALID")
	_forge = forge
	_builds = builds
	return _success({})


func forge_projection(weapon_id: String) -> Dictionary:
	return _forge.call("weapon_projection", snapshot(), weapon_id) if _forge != null else {}


func resolve_build(build_id: String) -> Dictionary:
	return _builds.call("resolve", snapshot(), build_id) if _builds != null else _failure(&"WORKSHOP_NOT_CONFIGURED")


func execute(command: Dictionary, expected_revision: int) -> Dictionary:
	var ready := _readiness(expected_revision)
	if not ready.ok:
		return ready
	var kind: Variant = command.get("kind")
	var producer: RefCounted
	if kind in ["forge_upgrade", "enchant_preference", "void_temper"]:
		producer = _forge
	elif kind in ["build_save", "build_remove"]:
		producer = _builds
	elif kind != "meta_unlock":
		return _failure(&"COMMAND_INVALID")
	var prepared: Dictionary
	var receipt: Dictionary = {}
	if kind == "meta_unlock":
		prepared = _profile.call("prepare_command", command, expected_revision)
	else:
		if producer == null:
			return _failure(&"WORKSHOP_NOT_CONFIGURED")
		var produced: Dictionary = producer.call("prepare_command", snapshot(), command, expected_revision)
		if not produced.ok:
			return produced
		prepared = _profile.call("prepare_candidate", produced.context.candidate)
		receipt = produced.context.duplicate(true)
		receipt.erase("candidate")
	if not prepared.ok:
		return prepared
	var persisted := _persist_ticket(prepared.context.ticket)
	if persisted.ok:
		persisted.context.merge(receipt, false)
	return persisted


func prepare_launch(request: Dictionary, expected_revision: int) -> Dictionary:
	var ready := _readiness(expected_revision)
	if not ready.ok:
		return ready
	var before := snapshot()
	if not before.active_launch_receipt.is_empty():
		return _failure(&"LAUNCH_ACTIVE")
	if not Catalog.exact_fields(request, ["seed", "difficulty", "character_id", "weapon_id", "time_abilities"]) or not Catalog.bounded_int(request.seed, 0, Catalog.MAX_VALUE) or request.difficulty not in ["normal", "hard", "nightmare"] or not before.unlocked_characters.has(request.character_id) or not before.unlocked_weapons.has(request.weapon_id) or before.launch_sequence == Catalog.MAX_VALUE:
		return _failure(&"LOADOUT_INVALID")
	var projected: Dictionary = MetaProjection.from_profile(before, _catalog)
	if not projected.ok:
		return projected
	var candidate := before.duplicate(true)
	candidate.launch_sequence += 1
	candidate.revision += 1
	var launch := {"schema_id": "meta_launch_receipt_v1", "sequence": candidate.launch_sequence, "run_id": "meta-run-%s-%d" % [_profile_id, candidate.launch_sequence], "difficulty": request.difficulty, "seed": int(request.seed), "character_id": request.character_id, "weapon_id": request.weapon_id, "time_abilities": request.time_abilities, "projection_digest": projected.context.projection.projection_digest}
	candidate.active_launch_receipt = launch.duplicate(true)
	var prepared: Dictionary = _profile.call("prepare_candidate", candidate)
	if not prepared.ok:
		return _failure(&"LOADOUT_INVALID")
	var persisted := _persist_ticket(prepared.context.ticket, {"active_run_state": {}})
	if persisted.ok:
		persisted.context["launch"] = launch.duplicate(true)
		persisted.context["projection"] = projected.context.projection.duplicate(true)
	return persisted


func settle_terminal(terminal: Dictionary, receipts: Array, expected_revision: int) -> Dictionary:
	var ready := _readiness(expected_revision)
	if not ready.ok:
		return ready
	var before := snapshot()
	var settlement: Dictionary = _settlement.call("prepare", before, before.active_launch_receipt, terminal, receipts)
	if not settlement.ok:
		return settlement
	var prepared: Dictionary = _profile.call("prepare_candidate", settlement.context.candidate)
	if not prepared.ok:
		return prepared
	var persisted := _persist_ticket(prepared.context.ticket, {"active_run_state": terminal})
	if persisted.ok:
		persisted.context["receipt"] = settlement.context.receipt.duplicate(true)
	return persisted


func abandon_run(active_run: Dictionary, expected_revision: int) -> Dictionary:
	var ready := _readiness(expected_revision)
	if not ready.ok:
		return ready
	var before := snapshot()
	var settlement: Dictionary = _settlement.call("prepare_abandon", before, before.active_launch_receipt, active_run)
	if not settlement.ok:
		return settlement
	var prepared: Dictionary = _profile.call("prepare_candidate", settlement.context.candidate)
	if not prepared.ok:
		return prepared
	return _persist_ticket(prepared.context.ticket, {"active_run_state": settlement.context.terminal})


func _persist_ticket(ticket: Dictionary, payload_changes: Dictionary = {}) -> Dictionary:
	var candidate: Dictionary = _profile.call("candidate_snapshot", ticket)
	if candidate.is_empty() or _busy:
		return _failure(&"TICKET_INVALID")
	_busy = true
	var primary = _save.call("inspect_profile", _profile_id, _save_domain)
	var next_payload := _payload.duplicate(true)
	if primary.ok:
		var durable: Dictionary = primary.payload.payload
		var state = Profile.new()
		if not durable.get("meta_profile_state") is Dictionary or not state.configure(_catalog, durable.meta_profile_state) or state.snapshot() != snapshot() or not _mirrors_match(durable, state.snapshot()):
			return _discard_failure(ticket, &"STALE_DURABLE_PROFILE")
		next_payload = durable.duplicate(true)
	elif primary.code != &"NOT_FOUND":
		return _discard_failure(ticket, primary.code)
	for key: String in payload_changes:
		next_payload[key] = payload_changes[key].duplicate(true)
	next_payload["meta_profile_state"] = candidate.duplicate(true)
	for field: String in MIRROR_FIELDS:
		next_payload[field] = _copy(candidate[field])
	var written = _save.call("save_profile", _profile_id, _save_domain, next_payload)
	var reconciled := false
	if not written.ok:
		# Only the promoted primary proves commit; loading could promote an uncommitted pending file.
		var inspected = _save.call("inspect_profile", _profile_id, _save_domain)
		if not inspected.ok or not _json_equal(inspected.payload.payload, _with_runtime_defaults(next_payload)):
			return _discard_failure(ticket, written.code)
		reconciled = true
	var committed: Dictionary = _profile.call("commit_candidate", ticket)
	_busy = false
	if not committed.ok:
		return _failure(&"INTEGRITY_FAILURE")
	_payload = _with_runtime_defaults(next_payload)
	return _success({"snapshot": snapshot(), "reconciled_committed_write": reconciled})


func _with_runtime_defaults(value: Dictionary) -> Dictionary:
	var normalized := value.duplicate(true)
	if not normalized.has("active_item_state"):
		normalized["active_item_state"] = Envelope.empty_active_item_state()
	for field: String in ["reward_effect_state", "active_run_state"]:
		if not normalized.has(field):
			normalized[field] = {}
	return normalized


func _discard_failure(ticket: Dictionary, code: StringName) -> Dictionary:
	_profile.call("discard_candidate", ticket)
	_busy = false
	return _failure(code)


func _readiness(expected_revision: int) -> Dictionary:
	if _profile == null or _busy:
		return _failure(&"BUSY" if _busy else &"NOT_CONFIGURED")
	if expected_revision != snapshot().revision:
		return _failure(&"STALE_REVISION")
	return _success({})


func _mirrors_match(value: Dictionary, profile: Dictionary) -> bool:
	for field: String in MIRROR_FIELDS:
		if value.has(field) and not _json_equal(value[field], profile[field]):
			return false
	return true


func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Array or value is Dictionary else value


func _json_equal(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(Envelope.canonical_json(left)) == JSON.parse_string(Envelope.canonical_json(right))


func _success(context: Dictionary) -> Dictionary:
	return {"ok": true, "code": &"OK", "context": context.duplicate(true)}


func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
