class_name GauntletsComboState
extends RefCounted

const SNAPSHOT_SCHEMA_VERSION := 1
const COMBO_TIMEOUT_FRAMES := 120
const MAX_COMBO_TIMEOUT_FRAMES := 480
const MAX_TRACKED_ACTIONS := 256
const PRIMARY_ACTION_IDS: Array[StringName] = [
	&"punch_1",
	&"punch_2",
	&"punch_3",
	&"punch_4",
	&"punch_5",
]

var _chain_step: int = 0
var _combo_count: int = 0
var _combo_timeout_frames_remaining: int = 0
var _combo_timeout_cap_frames: int = COMBO_TIMEOUT_FRAMES
var _hit_targets_by_token: Dictionary = {}
var _action_token_floor: int = 0


func peek_primary_action_id() -> StringName:
	return PRIMARY_ACTION_IDS[_chain_step]


func commit_primary_action(action_id: StringName, action_token: int) -> bool:
	if action_token <= 0 or action_id != peek_primary_action_id():
		return false
	_chain_step = (_chain_step + 1) % PRIMARY_ACTION_IDS.size()
	return true


func reset_chain() -> void:
	_chain_step = 0


func record_hit(
	action_token: int,
	generation: int,
	target_id: int,
	combo_gain: int,
	eligible: bool = true,
	timeout_frames: int = COMBO_TIMEOUT_FRAMES
) -> Dictionary:
	if (
		action_token <= 0
		or target_id <= 0
		or combo_gain < 0
		or timeout_frames <= 0
		or timeout_frames > MAX_COMBO_TIMEOUT_FRAMES
	):
		return _failure(&"INVALID_HIT")
	if generation != action_token:
		return _failure(&"STALE_GENERATION")
	if not eligible:
		return _success(0)
	if action_token <= _action_token_floor:
		return _failure(&"STALE_ACTION_TOKEN")

	var token_key := str(action_token)
	var targets_value: Variant = _hit_targets_by_token.get(token_key, {})
	if not targets_value is Dictionary:
		return _failure(&"INVALID_LEDGER")
	var targets := (targets_value as Dictionary).duplicate(true)
	var target_key := str(target_id)
	if targets.has(target_key):
		return _failure(&"DUPLICATE_TARGET")
	targets[target_key] = true
	_hit_targets_by_token[token_key] = targets
	_prune_hit_ledgers()

	_combo_count += combo_gain
	_combo_timeout_cap_frames = timeout_frames
	_combo_timeout_frames_remaining = timeout_frames
	return _success(combo_gain)


func advance_frames(elapsed_frames: int) -> bool:
	if elapsed_frames <= 0 or _combo_count <= 0:
		return false
	_combo_timeout_frames_remaining = maxi(
		0,
		_combo_timeout_frames_remaining - elapsed_frames
	)
	if _combo_timeout_frames_remaining > 0:
		return false
	reset_combo(&"timeout")
	return true


func notify_real_damage(damage_amount: float = 1.0) -> bool:
	if not is_finite(damage_amount) or damage_amount <= 0.0 or _combo_count <= 0:
		return false
	reset_combo(&"player_damaged")
	return true


func notify_dash_completed() -> void:
	# Dash is deliberately orthogonal to cross-chain Combo retention.
	pass


func reset_combo(_reason: StringName = &"reset") -> void:
	_combo_count = 0
	_combo_timeout_frames_remaining = 0
	_combo_timeout_cap_frames = COMBO_TIMEOUT_FRAMES


func reset(_reason: StringName = &"reset") -> void:
	_chain_step = 0
	_combo_count = 0
	_combo_timeout_frames_remaining = 0
	_combo_timeout_cap_frames = COMBO_TIMEOUT_FRAMES
	_hit_targets_by_token.clear()
	_action_token_floor = 0


func tier_snapshot() -> Dictionary:
	if _combo_count >= 30:
		return _tier(&"time_storm", 30, 1.25, 0.20, 0.20, 3, true)
	if _combo_count >= 20:
		return _tier(&"storm", 20, 1.20, 0.15, 0.10, 2, false)
	if _combo_count >= 15:
		return _tier(&"raging_gale", 15, 1.15, 0.12, 0.0, 1, false)
	if _combo_count >= 10:
		return _tier(&"strong_gale", 10, 1.10, 0.08, 0.0, 0, false)
	if _combo_count >= 5:
		return _tier(&"gale", 5, 1.10, 0.0, 0.0, 0, false)
	return _tier(&"none", 0, 1.0, 0.0, 0.0, 0, false)


func snapshot() -> Dictionary:
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"chain_step": _chain_step,
		"combo_count": _combo_count,
		"combo_timeout_frames_remaining": _combo_timeout_frames_remaining,
		"combo_timeout_cap_frames": _combo_timeout_cap_frames,
		"hit_targets_by_token": _hit_targets_by_token.duplicate(true),
		"action_token_floor": _action_token_floor,
	}


func restore_snapshot(value: Dictionary) -> bool:
	if not _valid_snapshot(value):
		return false
	_chain_step = int(value["chain_step"])
	_combo_count = int(value["combo_count"])
	_combo_timeout_frames_remaining = int(value["combo_timeout_frames_remaining"])
	_combo_timeout_cap_frames = int(value["combo_timeout_cap_frames"])
	_hit_targets_by_token = (value["hit_targets_by_token"] as Dictionary).duplicate(true)
	_action_token_floor = int(value["action_token_floor"])
	return true


func _tier(
	tier_id: StringName,
	minimum_combo: int,
	attack_speed_multiplier: float,
	critical_chance_bonus: float,
	time_damage_ratio: float,
	energy_return: int,
	slow_aura_enabled: bool
) -> Dictionary:
	return {
		"tier_id": str(tier_id),
		"minimum_combo": minimum_combo,
		"attack_speed_multiplier": attack_speed_multiplier,
		"critical_chance_bonus": critical_chance_bonus,
		"time_damage_ratio": time_damage_ratio,
		"energy_return": energy_return,
		"slow_aura": {
			"enabled": slow_aura_enabled,
			"radius_tiles": 2.0 if slow_aura_enabled else 0.0,
			"speed_multiplier": 0.85 if slow_aura_enabled else 1.0,
			"source_aware": slow_aura_enabled,
		},
	}


func _success(combo_gain: int) -> Dictionary:
	return {
		"ok": true,
		"code": &"OK",
		"combo_gain": combo_gain,
		"combo_count": _combo_count,
		"timeout_frames_remaining": _combo_timeout_frames_remaining,
		"tier": tier_snapshot(),
		"context": {},
	}


func _failure(code: StringName) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"combo_gain": 0,
		"combo_count": _combo_count,
		"timeout_frames_remaining": _combo_timeout_frames_remaining,
		"tier": tier_snapshot(),
		"context": {},
	}


func _prune_hit_ledgers() -> void:
	if _hit_targets_by_token.size() <= MAX_TRACKED_ACTIONS:
		return
	var tokens: Array[int] = []
	for token_value: Variant in _hit_targets_by_token.keys():
		var token := int(str(token_value))
		if token > 0:
			tokens.append(token)
	tokens.sort()
	while tokens.size() > MAX_TRACKED_ACTIONS:
		var removed: int = tokens.pop_front()
		_hit_targets_by_token.erase(str(removed))
		_action_token_floor = maxi(_action_token_floor, removed)


func _valid_snapshot(value: Dictionary) -> bool:
	if (
		int(value.get("schema_version", -1)) != SNAPSHOT_SCHEMA_VERSION
		or typeof(value.get("chain_step")) != TYPE_INT
		or int(value.get("chain_step", -1)) < 0
		or int(value.get("chain_step", -1)) >= PRIMARY_ACTION_IDS.size()
		or typeof(value.get("combo_count")) != TYPE_INT
		or int(value.get("combo_count", -1)) < 0
		or typeof(value.get("combo_timeout_frames_remaining")) != TYPE_INT
		or int(value.get("combo_timeout_frames_remaining", -1)) < 0
		or int(value.get("combo_timeout_frames_remaining", -1)) > MAX_COMBO_TIMEOUT_FRAMES
		or typeof(value.get("combo_timeout_cap_frames")) != TYPE_INT
		or int(value.get("combo_timeout_cap_frames", 0)) <= 0
		or int(value.get("combo_timeout_cap_frames", 0)) > MAX_COMBO_TIMEOUT_FRAMES
		or not value.get("hit_targets_by_token") is Dictionary
		or (value.get("hit_targets_by_token") as Dictionary).size() > MAX_TRACKED_ACTIONS
		or typeof(value.get("action_token_floor")) != TYPE_INT
		or int(value.get("action_token_floor", -1)) < 0
	):
		return false
	var combo_count := int(value["combo_count"])
	var remaining := int(value["combo_timeout_frames_remaining"])
	var cap := int(value["combo_timeout_cap_frames"])
	if (
		(combo_count == 0 and (remaining != 0 or cap != COMBO_TIMEOUT_FRAMES))
		or (combo_count > 0 and (remaining <= 0 or remaining > cap))
	):
		return false
	var floor := int(value["action_token_floor"])
	for token_value: Variant in (value["hit_targets_by_token"] as Dictionary).keys():
		var token_text := str(token_value)
		if not token_text.is_valid_int():
			return false
		var token := int(token_text)
		if token <= floor:
			return false
		var targets_value: Variant = (value["hit_targets_by_token"] as Dictionary)[token_value]
		if not targets_value is Dictionary or (targets_value as Dictionary).is_empty():
			return false
		for target_value: Variant in (targets_value as Dictionary).keys():
			var target_text := str(target_value)
			if not target_text.is_valid_int() or int(target_text) <= 0:
				return false
			if typeof((targets_value as Dictionary)[target_value]) != TYPE_BOOL or not bool((targets_value as Dictionary)[target_value]):
				return false
	return true
