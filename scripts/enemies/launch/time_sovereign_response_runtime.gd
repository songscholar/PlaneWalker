class_name TimeSovereignResponseRuntime
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const FIELDS := ["schema_version", "definition_digest", "identity", "runtime_frame", "terminal", "watermark", "pending", "active", "cooldown_until_frame", "last_rewind"]
const RECEIPT_FIELDS := ["id", "run_id", "owner_generation", "action_generation", "action_token", "ability_id", "runtime_frame", "endpoint", "facing"]
const ACTIVE_FIELDS := ["receipt", "attack_generation", "start_frame", "activation_frame", "expires_frame", "watch_damage", "hit_claims", "cancelled", "shattered", "recovery_granted"]
const ABILITIES := ["stop", "rewind", "accelerate", "rift"]
const MAX_PENDING := 4
const MAX_WATCH_CLAIMS := 10000
const MAX_FRAME := 2147483647 - Contract.MAX_FRAME

var _state := {}
var _mechanisms := {}


func configure(identity: Dictionary, mechanisms: Dictionary) -> bool:
	if not Contract.exact_fields(identity, ["run_id", "hostile_source_id", "next_generation_floor", "runtime_frame", "seed"]):
		return false
	_mechanisms = mechanisms.duplicate(true)
	_state = {"schema_version": 1, "definition_digest": var_to_bytes(mechanisms).hex_encode().sha256_text(), "identity": identity.duplicate(true), "runtime_frame": int(identity.runtime_frame), "terminal": false, "watermark": {}, "pending": [], "active": {}, "cooldown_until_frame": int(identity.runtime_frame), "last_rewind": {}}
	return true


func initial_at_frame(frame: int, terminal: bool) -> Dictionary:
	var result := _state.duplicate(true)
	result.runtime_frame = frame
	result.terminal = terminal
	result.watermark = {}
	result.pending = []
	result.active = {}
	result.cooldown_until_frame = frame
	result.last_rewind = {}
	return result


func snapshot() -> Dictionary:
	return _state.duplicate(true)


static func receipt_id(value: Dictionary) -> String:
	return JSON.stringify([value.run_id, value.owner_generation, value.action_generation, value.action_token]).sha256_text()


static func valid_receipt(value: Variant) -> bool:
	if not value is Dictionary or not Contract.exact_fields(value, RECEIPT_FIELDS):
		return false
	if typeof(value.id) != TYPE_STRING or typeof(value.run_id) != TYPE_STRING or value.run_id.is_empty() or value.run_id.length() > 128 or value.ability_id not in ABILITIES or not Contract.integer_in_range(value.runtime_frame, 0, MAX_FRAME) or not Contract.valid_point(value.endpoint) or not Contract.valid_point(value.facing, 1):
		return false
	for field: String in ["owner_generation", "action_generation", "action_token"]:
		if not Contract.integer_in_range(value[field], 1, MAX_FRAME):
			return false
	return value.id == receipt_id(value) and is_equal_approx(Vector2(float(value.facing.x), float(value.facing.y)).length(), 1.0)


static func _after(value: Dictionary, previous: Dictionary) -> bool:
	for field: String in ["owner_generation", "action_generation", "action_token"]:
		if value[field] != previous[field]:
			return value[field] > previous[field]
	return false


func accept_receipt(value: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.terminal or not valid_receipt(value) or value.run_id != _state.identity.run_id or value.runtime_frame not in [int(_state.runtime_frame), int(_state.runtime_frame) + 1] or not _state.watermark.is_empty() and not _after(value, _state.watermark):
		return {"ok": false}
	_state.watermark = value.duplicate(true)
	if value.ability_id == "rewind":
		_state.last_rewind = {"receipt": value.duplicate(true), "echo_claimed": false}
	var queued: bool = _state.pending.size() < MAX_PENDING
	if queued:
		_state.pending.append(value.duplicate(true))
	return {"ok": true, "queued": queued}


func advance_frame(frame: int) -> bool:
	if _state.is_empty() or frame != int(_state.runtime_frame) + 1 or frame > MAX_FRAME:
		return false
	_state.runtime_frame = frame
	return true


func pending_request(frame: int) -> Dictionary:
	if _state.is_empty() or _state.terminal or _state.pending.is_empty() or frame != int(_state.runtime_frame) or frame < int(_state.cooldown_until_frame):
		return {}
	var receipt: Dictionary = _state.pending[0]
	if frame < int(receipt.runtime_frame) + (int(_mechanisms.counter_stop_delay_frames) if receipt.ability_id == "stop" else 0):
		return {}
	return {"action_id": "traitor.counter_" + str(receipt.ability_id), "receipt": receipt.duplicate(true)}


func commit_request(request: Dictionary, generation: int, frame: int, phase_index: int) -> bool:
	if request != pending_request(frame) or request.is_empty() or not Contract.integer_in_range(generation, 1, MAX_FRAME):
		return false
	_state.pending.pop_front()
	_state.active = {"receipt": request.receipt.duplicate(true), "attack_generation": generation, "start_frame": frame, "activation_frame": -1, "expires_frame": -1, "watch_damage": 0.0, "hit_claims": [], "cancelled": false, "shattered": false, "recovery_granted": false}
	_state.cooldown_until_frame = frame + int(_mechanisms.response_shared_cooldown_p1_frames if phase_index == 0 else _mechanisms.response_shared_cooldown_p2_frames)
	return true


func observe_action(action: Dictionary) -> void:
	if _state.active.is_empty():
		return
	var active: Dictionary = _state.active
	if action.action_id == "traitor.counter_" + str(active.receipt.ability_id) and not action.geometry_generations.is_empty() and action.geometry_generations[0] == active.attack_generation:
		if action.phase == "ACTIVE" and active.activation_frame < 0:
			active.activation_frame = int(_state.runtime_frame)
			active.expires_frame = int(_state.runtime_frame) + (119 if active.receipt.ability_id == "accelerate" else 0)
	elif active.activation_frame < 0:
		active.cancelled = true


func accept_watch_hit(value: Dictionary, action: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.terminal or not Contract.exact_fields(value, ["fact_id", "runtime_frame", "amount", "accelerated", "rewind_echo"]) or typeof(value.fact_id) != TYPE_STRING or value.fact_id.is_empty() or value.fact_id.length() > 128 or value.runtime_frame not in [int(_state.runtime_frame), int(_state.runtime_frame) + 1] or not Contract.number_in_range(value.amount, 0.000001, 1000000.0) or typeof(value.accelerated) != TYPE_BOOL or typeof(value.rewind_echo) != TYPE_BOOL:
		return {"ok": false}
	var result := {"ok": true, "cancel_action": false, "shatter_zone": false, "exposure_frames": 0, "recovery_frames": 0}
	if value.rewind_echo and not _state.last_rewind.is_empty() and not _state.last_rewind.echo_claimed and int(value.runtime_frame) <= int(_state.last_rewind.receipt.runtime_frame) + 360:
		_state.last_rewind.echo_claimed = true
		result.exposure_frames = int(_mechanisms.counter_rewind_echo_exposure_frames)
	if _state.active.is_empty():
		return result
	var active: Dictionary = _state.active
	if active.cancelled or active.shattered or active.hit_claims.has(value.fact_id):
		return result
	if active.receipt.ability_id == "stop" and action.action_id == "traitor.counter_stop" and action.phase == "WARNING":
		active.hit_claims.append(value.fact_id)
		active.watch_damage = minf(float(_mechanisms.counter_stop_cancel_damage), float(active.watch_damage) + float(value.amount))
		if active.watch_damage >= float(_mechanisms.counter_stop_cancel_damage):
			active.cancelled = true
			result.cancel_action = true
			result.exposure_frames = int(_mechanisms.counter_stop_exposure_frames)
			result.recovery_frames = int(_mechanisms.counter_stop_exposure_frames)
	elif active.receipt.ability_id == "accelerate" and value.accelerated and active.activation_frame >= 0 and int(value.runtime_frame) <= int(active.expires_frame):
		active.hit_claims.append(value.fact_id)
		if active.hit_claims.size() == int(_mechanisms.counter_accelerate_shatter_hits):
			active.shattered = true
			result.shatter_zone = true
			result.cancel_action = action.action_id == "traitor.counter_accelerate"
			result.exposure_frames = int(_mechanisms.counter_accelerate_exposure_frames)
			result.recovery_frames = int(_mechanisms.counter_accelerate_exposure_frames)
	return result


func grant_rift_recovery(generation: int) -> bool:
	if _state.active.is_empty() or _state.active.attack_generation != generation or _state.active.receipt.ability_id != "rift" or _state.active.recovery_granted:
		return false
	_state.active.recovery_granted = true
	return true


func zone_alive(generation: int) -> bool:
	return not _state.is_empty() and not _state.terminal and not _state.active.is_empty() and _state.active.attack_generation == generation and not _state.active.cancelled and not _state.active.shattered


func retire() -> void:
	_state.terminal = true
	_state.pending = []
	if not _state.active.is_empty():
		_state.active.cancelled = true


func can_restore_snapshot(value: Dictionary) -> bool:
	if _state.is_empty() or not Contract.exact_fields(value, FIELDS) or value.schema_version != 1 or value.definition_digest != _state.definition_digest or value.identity != _state.identity or not Contract.integer_in_range(value.runtime_frame, int(_state.identity.runtime_frame), MAX_FRAME) or typeof(value.terminal) != TYPE_BOOL or not value.watermark is Dictionary or not value.pending is Array or value.pending.size() > MAX_PENDING or not value.active is Dictionary or not Contract.integer_in_range(value.cooldown_until_frame, int(_state.identity.runtime_frame), MAX_FRAME):
		return false
	if not value.watermark.is_empty() and not _receipt_in_state(value.watermark, value):
		return false
	if value.watermark.is_empty() and (not value.pending.is_empty() or not value.active.is_empty() or not value.last_rewind.is_empty()):
		return false
	var previous := {}
	for receipt: Variant in value.pending:
		if not _receipt_in_state(receipt, value) or not previous.is_empty() and not _after(receipt, previous) or value.watermark.is_empty() or _after(receipt, value.watermark):
			return false
		previous = receipt
	if value.terminal and not value.pending.is_empty():
		return false
	if not value.last_rewind is Dictionary:
		return false
	if not value.last_rewind.is_empty() and (not Contract.exact_fields(value.last_rewind, ["receipt", "echo_claimed"]) or not _receipt_in_state(value.last_rewind.receipt, value) or value.last_rewind.receipt.ability_id != "rewind" or typeof(value.last_rewind.echo_claimed) != TYPE_BOOL or _after(value.last_rewind.receipt, value.watermark)):
		return false
	if value.active.is_empty():
		return true
	var active: Dictionary = value.active
	if not Contract.exact_fields(active, ACTIVE_FIELDS) or not _receipt_in_state(active.receipt, value) or value.watermark.is_empty() or _after(active.receipt, value.watermark) or not Contract.integer_in_range(active.attack_generation, int(_state.identity.next_generation_floor), MAX_FRAME) or not Contract.integer_in_range(active.start_frame, int(active.receipt.runtime_frame), int(value.runtime_frame)) or not Contract.integer_in_range(active.activation_frame, -1, int(value.runtime_frame)) or not Contract.integer_in_range(active.expires_frame, -1, MAX_FRAME) or not Contract.number_in_range(active.watch_damage, 0.0, float(_mechanisms.counter_stop_cancel_damage)) or not active.hit_claims is Array or active.hit_claims.size() > MAX_WATCH_CLAIMS:
		return false
	if not value.pending.is_empty() and not _after(value.pending[0], active.receipt) or int(value.cooldown_until_frame) - int(active.start_frame) not in [int(_mechanisms.response_shared_cooldown_p1_frames), int(_mechanisms.response_shared_cooldown_p2_frames)]:
		return false
	for field: String in ["cancelled", "shattered", "recovery_granted"]:
		if typeof(active[field]) != TYPE_BOOL:
			return false
	if active.receipt.ability_id == "stop" and active.start_frame < int(active.receipt.runtime_frame) + int(_mechanisms.counter_stop_delay_frames):
		return false
	if active.activation_frame < 0 and active.expires_frame != -1 or active.activation_frame >= 0 and (active.activation_frame < active.start_frame + 45 or active.expires_frame != active.activation_frame + (119 if active.receipt.ability_id == "accelerate" else 0)):
		return false
	var seen := {}
	for claim: Variant in active.hit_claims:
		if typeof(claim) != TYPE_STRING or claim.is_empty() or claim.length() > 128 or seen.has(claim):
			return false
		seen[claim] = true
	if active.shattered and (active.receipt.ability_id != "accelerate" or active.hit_claims.size() != int(_mechanisms.counter_accelerate_shatter_hits)) or active.recovery_granted and active.receipt.ability_id != "rift" or value.terminal and not active.cancelled:
		return false
	return true


func _receipt_in_state(receipt: Variant, value: Dictionary) -> bool:
	return valid_receipt(receipt) and receipt.run_id == value.identity.run_id and receipt.runtime_frame >= int(value.identity.runtime_frame) and receipt.runtime_frame <= int(value.runtime_frame) + 1


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	_state = value.duplicate(true)
	return true
