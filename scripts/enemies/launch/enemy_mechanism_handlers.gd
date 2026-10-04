class_name EnemyMechanismHandlers
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const MAX_DAMAGE_CLAIMS := 4096
const ACTION_IDS := {
	"shattered_sentinel": ["shield_sweep", "boulder_slam"],
	"corrosive_moth": ["corrosive_spit", "corrosive_barrage"],
	"stone_shell_strider": ["shell_charge", "bite", "shell_shock"],
	"ruins_wraith": ["spirit_detonation", "spirit_split"],
	"rift_watcher": ["nourish", "rift_pulse", "rift_bind"],
}
const STATE_FIELDS := {
	"shattered_sentinel": ["first_attack_ready_frame", "damage_claims", "retreat_remaining_frames", "retreat_direction"],
	"corrosive_moth": ["first_attack_ready_frame", "damage_claims", "death_pool_reserved"],
	"stone_shell_strider": ["first_attack_ready_frame", "damage_claims", "shell_remaining_frames", "open_remaining_frames", "shell_cycle", "shell_shock_used"],
	"ruins_wraith": ["first_attack_ready_frame", "damage_claims", "windup_damage", "stagger_remaining_frames", "detonation_consumed"],
	"rift_watcher": ["first_attack_ready_frame", "damage_claims", "healing_expenditure", "death_debuff_reserved"],
}


static func action_ids(kind: String, elite: bool) -> Array[String]:
	var result: Array[String] = []
	if not ACTION_IDS.has(kind):
		return result
	var ids: Array = ACTION_IDS[kind]
	for index: int in range(ids.size() if elite else ids.size() - 1):
		result.append(kind + "." + ids[index])
	return result


static func make_state(kind: String, first_attack_ready_frame: int) -> Dictionary:
	var state := {"first_attack_ready_frame": first_attack_ready_frame, "damage_claims": []}
	match kind:
		"shattered_sentinel": state.merge({"retreat_remaining_frames": 0, "retreat_direction": {"x": 0.0, "y": 0.0}})
		"corrosive_moth": state.merge({"death_pool_reserved": false})
		"stone_shell_strider": state.merge({"shell_remaining_frames": 0, "open_remaining_frames": 0, "shell_cycle": 0, "shell_shock_used": false})
		"ruins_wraith": state.merge({"windup_damage": 0.0, "stagger_remaining_frames": 0, "detonation_consumed": false})
		"rift_watcher": state.merge({"healing_expenditure": {}, "death_debuff_reserved": false})
		_: return {}
	return state


static func valid_state(kind: String, authored: Dictionary, state: Dictionary, initial_ready_frame: int) -> bool:
	if not STATE_FIELDS.has(kind) or not Contract.exact_fields(state, STATE_FIELDS[kind]) or state.first_attack_ready_frame != initial_ready_frame or not state.damage_claims is Array or state.damage_claims.size() > MAX_DAMAGE_CLAIMS:
		return false
	var seen: Dictionary = {}
	for claim: Variant in state.damage_claims:
		if typeof(claim) != TYPE_STRING or claim.length() != 64 or not claim.is_valid_hex_number(false) or seen.has(claim):
			return false
		seen[claim] = true
	match kind:
		"shattered_sentinel":
			if not _integer(state.retreat_remaining_frames, 0, authored.retreat_frames) or not Contract.valid_point(state.retreat_direction, 1.0):
				return false
			return state.retreat_remaining_frames == 0 or is_equal_approx(_vector(state.retreat_direction).length(), 1.0)
		"corrosive_moth": return typeof(state.death_pool_reserved) == TYPE_BOOL
		"stone_shell_strider":
			return _integer(state.shell_remaining_frames, 0, authored.shell_frames) and _integer(state.open_remaining_frames, 0, authored.open_frames) and _integer(state.shell_cycle, 0, 2147483646) and typeof(state.shell_shock_used) == TYPE_BOOL and (state.shell_remaining_frames == 0 or state.open_remaining_frames == 0)
		"ruins_wraith":
			return Contract.number_in_range(state.windup_damage, 0.0, authored.windup_interrupt_damage) and state.windup_damage < authored.windup_interrupt_damage and _integer(state.stagger_remaining_frames, 0, authored.stagger_frames) and typeof(state.detonation_consumed) == TYPE_BOOL
		"rift_watcher":
			if typeof(state.death_debuff_reserved) != TYPE_BOOL or not state.healing_expenditure is Dictionary or state.healing_expenditure.size() > 8:
				return false
			for source: Variant in state.healing_expenditure:
				if typeof(source) != TYPE_STRING or source.is_empty() or not Contract.number_in_range(state.healing_expenditure[source], 0.0, 1000000.0):
					return false
			return true
	return false


static func accept_damage(kind: String, authored: Dictionary, state: Dictionary, action: Dictionary, fact: Dictionary) -> Dictionary:
	var claim := str(fact.fact_id).sha256_text()
	if state.damage_claims.has(claim) or state.damage_claims.size() >= MAX_DAMAGE_CLAIMS:
		return {"ok": false}
	var next := state.duplicate(true)
	next.damage_claims.append(claim)
	var cancel_action: bool = fact.hp_after <= 0.0
	if kind == "stone_shell_strider" and not cancel_action and next.shell_remaining_frames == 0 and next.open_remaining_frames == 0:
		next.shell_remaining_frames = authored.shell_frames
		next.shell_cycle += 1
		next.shell_shock_used = false
	if kind == "ruins_wraith" and action.phase == "WARNING" and action.action_id == "ruins_wraith.spirit_detonation":
		next.windup_damage += float(fact.amount)
		if next.windup_damage >= authored.windup_interrupt_damage or cancel_action:
			cancel_action = true
			next.windup_damage = 0.0
			next.stagger_remaining_frames = authored.stagger_frames if fact.hp_after > 0.0 else 0
	return {"ok": true, "state": next, "cancel_action": cancel_action}


static func advance(kind: String, authored: Dictionary, state: Dictionary, before_action: Dictionary, after_action: Dictionary) -> Dictionary:
	var next := state.duplicate(true)
	var requests: Array[Dictionary] = []
	match kind:
		"shattered_sentinel":
			if next.retreat_remaining_frames > 0:
				next.retreat_remaining_frames -= 1
			if before_action.phase == "ACTIVE" and after_action.phase == "RECOVERY" and before_action.action_id == "shattered_sentinel.shield_sweep":
				next.retreat_remaining_frames = authored.retreat_frames
				var direction := -_vector(before_action.committed_aim)
				next.retreat_direction = {"x": direction.x, "y": direction.y}
		"stone_shell_strider":
			if next.shell_remaining_frames > 0:
				next.shell_remaining_frames -= 1
				if next.shell_remaining_frames == 0:
					next.open_remaining_frames = authored.open_frames
			elif next.open_remaining_frames > 0:
				next.open_remaining_frames -= 1
		"ruins_wraith":
			if next.stagger_remaining_frames > 0:
				next.stagger_remaining_frames -= 1
			if before_action.phase == "IDLE" and after_action.phase == "WARNING":
				next.windup_damage = 0.0
			if before_action.phase == "ACTIVE" and after_action.phase == "RECOVERY" and before_action.action_id == "ruins_wraith.spirit_detonation" and not next.detonation_consumed:
				next.detonation_consumed = true
				requests.append({"kind": "consume_actor", "attack_generation": before_action.geometry_generations[0], "hit_index": 63})
	return {"state": next, "requests": requests}


static func action_available(kind: String, state: Dictionary, action_id: String) -> bool:
	if kind == "shattered_sentinel":
		return state.retreat_remaining_frames == 0
	if kind == "ruins_wraith":
		return state.stagger_remaining_frames == 0 and not state.detonation_consumed and not action_id.ends_with(".spirit_split")
	if kind == "stone_shell_strider" and action_id.ends_with(".shell_shock"):
		return state.shell_remaining_frames > 0 and not state.shell_shock_used
	return true


static func action_started(kind: String, state: Dictionary, action_id: String) -> Dictionary:
	var next := state.duplicate(true)
	if kind == "stone_shell_strider" and action_id.ends_with(".shell_shock"):
		next.shell_shock_used = true
	if kind == "ruins_wraith" and action_id.ends_with(".spirit_detonation"):
		next.windup_damage = 0.0
	return next


static func damage_taken_multiplier(kind: String, authored: Dictionary, state: Dictionary) -> float:
	if kind == "stone_shell_strider":
		if state.shell_remaining_frames > 0:
			return float(authored.shell_damage_multiplier)
		if state.open_remaining_frames > 0:
			return float(authored.open_damage_multiplier)
	return 1.0


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) == TYPE_INT and Contract.integer_in_range(value, minimum, maximum)


static func _vector(value: Dictionary) -> Vector2:
	return Vector2(float(value.x), float(value.y))
