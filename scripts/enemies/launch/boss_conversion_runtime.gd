class_name BossConversionRuntime
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const IDENTITY_FIELDS: Array[String] = ["run_id", "hostile_source_id", "runtime_frame"]
const FIELDS: Array[String] = ["schema_version", "identity", "runtime_frame", "generation_floor", "claims", "weapon_sources", "poise"]
const EXPOSURE_FIELDS: Array[String] = ["schema_version", "identity", "claimed_stop_generation_floor", "tail_state", "remaining_tail_frames", "claims"]
const NATIVE_IDENTITY_FIELDS: Array[String] = ["run_id", "room_id", "encounter_id", "encounter_spawn_id", "encounter_enemy_id", "hostile_source_id", "hostile_next_generation_floor", "committed_attack_generation"]
const CLAIM_FIELDS: Array[String] = ["stop_generation", "granted_frames", "remaining_frames", "state"]
const SOURCE_FIELDS: Array[String] = ["id", "expires_through_frame"]
const MAX_FRAME := 2147447647
const MAX_CLAIMS := 32
const MAX_SOURCES := 64
var _state: Dictionary = {}


func configure(identity: Dictionary) -> bool:
	_state.clear()
	if not Contract.exact_fields(identity, IDENTITY_FIELDS) or not _stable_id(identity.run_id) or not _stable_id(identity.hostile_source_id) or not Contract.integer_in_range(identity.runtime_frame, 0, MAX_FRAME):
		return false
	_state = {"schema_version": 1, "identity": identity.duplicate(true), "runtime_frame": identity.runtime_frame, "generation_floor": 0, "claims": [], "weapon_sources": [], "poise": 0.0}
	return true


func extend_character(stop_generation: int, frames: int, has_window: bool, must_wait: bool) -> bool:
	if _state.is_empty() or stop_generation <= int(_state.generation_floor) or stop_generation > MAX_FRAME or frames <= 0 or frames > 30 or _state.claims.size() >= MAX_CLAIMS or not has_window:
		return false
	_state.generation_floor = stop_generation
	_state.claims.append({"stop_generation": stop_generation, "granted_frames": frames, "remaining_frames": frames, "state": "pending" if must_wait else "active"})
	_sync_tail(must_wait)
	return true


func convert_weapon(source_id: String, recovery_frames: int, exposure_frames: int, poise_damage: float, phase: String, exposed: bool, poise_threshold: float, poise_extension_frames: int) -> Dictionary:
	if _state.is_empty() or not _stable_id(source_id) or recovery_frames < 0 or recovery_frames > Contract.MAX_FRAME or exposure_frames < 0 or exposure_frames > Contract.MAX_FRAME or not Contract.number_in_range(poise_damage, 0.0, 1000000.0) or phase == "WARNING" or phase != "RECOVERY" and not exposed or _state.weapon_sources.size() >= MAX_SOURCES:
		return {"ok": false}
	for source: Dictionary in _state.weapon_sources:
		if source.id == source_id:
			return {"ok": false}
	var recovery := mini(90, recovery_frames) if phase == "RECOVERY" else 0
	var exposure := mini(90, exposure_frames)
	var next_poise := minf(poise_threshold, float(_state.poise) + poise_damage)
	if poise_threshold > 0.0 and next_poise >= poise_threshold:
		next_poise = 0.0
		recovery = mini(90, recovery + poise_extension_frames) if phase == "RECOVERY" else recovery
		exposure = maxi(exposure, poise_extension_frames)
	var lifetime := maxi(1, maxi(recovery, exposure))
	if int(_state.runtime_frame) > MAX_FRAME - lifetime:
		return {"ok": false}
	_state.weapon_sources.append({"id": source_id, "expires_through_frame": int(_state.runtime_frame) + lifetime})
	_state.weapon_sources.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	_state.poise = next_poise
	return {"ok": true, "recovery_frames": recovery, "exposure_frames": exposure}


func advance_frame(frame: int, must_wait: bool) -> bool:
	if _state.is_empty() or frame != int(_state.runtime_frame) + 1 or frame > MAX_FRAME:
		return false
	_state.runtime_frame = frame
	_state.poise = maxf(0.0, float(_state.poise) - 8.0 / 60.0)
	var sources: Array = []
	for source: Dictionary in _state.weapon_sources:
		if int(source.expires_through_frame) >= frame:
			sources.append(source)
	_state.weapon_sources = sources
	var was_active := is_character_exposed()
	_sync_tail(must_wait)
	if was_active and is_character_exposed():
		_state.claims[0].remaining_frames -= 1
		if int(_state.claims[0].remaining_frames) == 0:
			_state.claims.pop_front()
	return true


func is_character_exposed() -> bool:
	return not _state.is_empty() and not _state.claims.is_empty() and _state.claims[0].state == "active"


func synchronize_tail(must_wait: bool) -> void:
	if not _state.is_empty():
		_sync_tail(must_wait)


func exposure_snapshot(identity: Dictionary) -> Dictionary:
	if _state.is_empty() or not _valid_native_identity(identity):
		return {}
	return {"schema_version": 1, "identity": identity.duplicate(true), "claimed_stop_generation_floor": int(_state.generation_floor), "tail_state": "idle" if _state.claims.is_empty() else str(_state.claims[0].state), "remaining_tail_frames": _remaining(), "claims": _state.claims.duplicate(true)}


func can_restore_exposure(value: Dictionary, identity: Dictionary, must_wait: bool, authorized: bool = false) -> bool:
	if _state.is_empty() or not Contract.exact_fields(value, EXPOSURE_FIELDS) or not Contract.integer_in_range(value.schema_version, 1, 1) or not value.identity is Dictionary or not _valid_native_identity(value.identity) or value.identity != identity:
		return false
	if not Contract.integer_in_range(value.claimed_stop_generation_floor, 0, MAX_FRAME) or typeof(value.tail_state) != TYPE_STRING or not Contract.integer_in_range(value.remaining_tail_frames, 0, 960) or not _valid_claims(value.claims, int(value.claimed_stop_generation_floor)):
		return false
	if not authorized and (int(value.claimed_stop_generation_floor) < int(_state.generation_floor) or int(value.claimed_stop_generation_floor) == int(_state.generation_floor) and int(value.remaining_tail_frames) > _remaining()):
		return false
	var state: String = "idle" if value.claims.is_empty() else str(value.claims[0].state)
	var remaining := 0
	for claim: Dictionary in value.claims:
		remaining += int(claim.remaining_frames)
	return value.tail_state == state and int(value.remaining_tail_frames) == remaining and (state == "idle" or (state == "pending") == must_wait)


func restore_exposure(value: Dictionary, identity: Dictionary, must_wait: bool, authorized: bool = false) -> bool:
	if not can_restore_exposure(value, identity, must_wait, authorized):
		return false
	_state.generation_floor = value.claimed_stop_generation_floor
	_state.claims = value.claims.duplicate(true)
	return true


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func matches_snapshot(value: Dictionary) -> bool:
	return _state == value


func can_restore_snapshot(value: Dictionary) -> bool:
	if _state.is_empty() or not Contract.exact_fields(value, FIELDS) or not Contract.integer_in_range(value.schema_version, 1, 1) or value.identity != _state.identity or not Contract.integer_in_range(value.runtime_frame, int(_state.identity.runtime_frame), MAX_FRAME) or not Contract.integer_in_range(value.generation_floor, 0, MAX_FRAME) or not _valid_claims(value.claims, int(value.generation_floor)) or not Contract.number_in_range(value.poise, 0.0, 300.0) or not value.weapon_sources is Array or value.weapon_sources.size() > MAX_SOURCES:
		return false
	var previous := ""
	for candidate: Variant in value.weapon_sources:
		if not candidate is Dictionary or not Contract.exact_fields(candidate, SOURCE_FIELDS) or not _stable_id(candidate.id) or str(candidate.id) <= previous or not Contract.integer_in_range(candidate.expires_through_frame, int(value.runtime_frame), int(value.runtime_frame) + 90):
			return false
		previous = candidate.id
	return true


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	_state = value.duplicate(true)
	return true


func cancel() -> void:
	if not _state.is_empty():
		_state.claims.clear()
		_state.weapon_sources.clear()
		_state.poise = 0.0


func _sync_tail(must_wait: bool) -> void:
	for claim: Dictionary in _state.claims:
		claim.state = "pending" if must_wait else "active"


func _remaining() -> int:
	var remaining := 0
	for claim: Dictionary in _state.get("claims", []):
		remaining += int(claim.remaining_frames)
	return remaining


func _valid_native_identity(value: Dictionary) -> bool:
	if not Contract.exact_fields(value, NATIVE_IDENTITY_FIELDS):
		return false
	for field: String in NATIVE_IDENTITY_FIELDS.slice(0, 6):
		if typeof(value[field]) not in [TYPE_STRING, TYPE_STRING_NAME] or str(value[field]).is_empty() or str(value[field]).length() > 128:
			return false
	return str(value.run_id) == _state.identity.run_id and str(value.hostile_source_id) == _state.identity.hostile_source_id and Contract.integer_in_range(value.hostile_next_generation_floor, 1, MAX_FRAME) and Contract.integer_in_range(value.committed_attack_generation, 0, int(value.hostile_next_generation_floor) - 1)


static func _valid_claims(value: Variant, floor: int) -> bool:
	if not value is Array or value.size() > MAX_CLAIMS:
		return false
	var previous := 0
	var state := ""
	for candidate: Variant in value:
		if not candidate is Dictionary or not Contract.exact_fields(candidate, CLAIM_FIELDS) or not Contract.integer_in_range(candidate.stop_generation, previous + 1, floor) or not Contract.integer_in_range(candidate.granted_frames, 1, 30) or not Contract.integer_in_range(candidate.remaining_frames, 1, int(candidate.granted_frames)) or candidate.state not in ["pending", "active"] or not state.is_empty() and candidate.state != state:
			return false
		previous = candidate.stop_generation
		state = candidate.state
	return value.is_empty() or previous == floor


static func _stable_id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty() and value == value.strip_edges() and value.length() <= 64
