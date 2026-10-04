class_name EnemyMechanismHandlers
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Definition := preload("res://scripts/enemies/launch/enemy_definition.gd")
const MAX_DAMAGE_CLAIMS := 4096
const ACTION_IDS := Definition.ACTION_IDS
const COMMON_FIELDS := ["first_attack_ready_frame", "damage_claims", "hp_after", "last_action_id", "consecutive_actions"]
const STATE_FIELDS := {
	"shattered_sentinel": ["retreat_remaining_frames", "retreat_direction"],
	"corrosive_moth": ["death_pool_reserved"],
	"stone_shell_strider": ["shell_remaining_frames", "open_remaining_frames", "shell_cycle", "shell_shock_used", "shell_shock_cycle"],
	"ruins_wraith": ["windup_damage", "stagger_remaining_frames", "detonation_consumed"],
	"rift_watcher": ["healing_expenditure", "death_debuff_reserved"],
	"void_hunter": ["retreat_remaining_px", "retreat_direction"],
	"void_archer": [], "bramble_mage": [], "void_spore": ["burst_consumed"], "forest_caller": [],
	"shadow_lurker": ["burrow_remaining_frames"],
	"chrono_guard": ["revival_used", "recovery_remaining_frames"],
	"rift_weaver": [], "blink_striker": [], "rewind_priest": [], "chrono_storm_elemental": [],
	"eternal_hound": ["dormancy_used", "dormancy_remaining_frames", "sigil_hp", "sigil_claims"],
	"forge_titan": ["overheat_used", "overheat_remaining_frames", "explosion_reserved"],
	"void_web_weaver": [], "phase_ranger": [],
	"chaos_amalgam": ["form_id", "form_elapsed_frames", "switch_remaining_frames"],
	"plane_ripper": [],
}


static func action_ids(kind: String, elite: bool) -> Array[String]:
	var result: Array[String] = []
	if not ACTION_IDS.has(kind):
		return result
	for id: String in ACTION_IDS[kind].actions:
		result.append(id)
	if elite:
		for id: String in ACTION_IDS[kind].elite_actions:
			result.append(id)
	return result


static func make_state(kind: String, first_attack_ready_frame: int, max_hp: float, authored: Dictionary) -> Dictionary:
	var state := {"first_attack_ready_frame": first_attack_ready_frame, "damage_claims": [], "hp_after": max_hp, "last_action_id": "", "consecutive_actions": 0}
	match kind:
		"shattered_sentinel": state.merge({"retreat_remaining_frames": 0, "retreat_direction": {"x": 0.0, "y": 0.0}})
		"corrosive_moth": state.merge({"death_pool_reserved": false})
		"stone_shell_strider": state.merge({"shell_remaining_frames": 0, "open_remaining_frames": 0, "shell_cycle": 0, "shell_shock_used": false, "shell_shock_cycle": 0})
		"ruins_wraith": state.merge({"windup_damage": 0.0, "stagger_remaining_frames": 0, "detonation_consumed": false})
		"rift_watcher": state.merge({"healing_expenditure": {}, "death_debuff_reserved": false})
		"void_hunter": state.merge({"retreat_remaining_px": 0.0, "retreat_direction": {"x": 0.0, "y": 0.0}})
		"void_spore": state["burst_consumed"] = false
		"shadow_lurker": state["burrow_remaining_frames"] = int(authored.burrow_cap_frames)
		"chrono_guard": state.merge({"revival_used": false, "recovery_remaining_frames": 0})
		"eternal_hound": state.merge({"dormancy_used": false, "dormancy_remaining_frames": 0, "sigil_hp": 0.0, "sigil_claims": []})
		"forge_titan": state.merge({"overheat_used": false, "overheat_remaining_frames": 0, "explosion_reserved": false})
		"chaos_amalgam": state.merge({"form_id": "red", "form_elapsed_frames": 0, "switch_remaining_frames": 0})
		_:
			if not STATE_FIELDS.has(kind):
				return {}
	return state


static func valid_state(kind: String, authored: Dictionary, state: Dictionary, initial_ready_frame: int, max_hp: float) -> bool:
	if not STATE_FIELDS.has(kind) or not Contract.exact_fields(state, COMMON_FIELDS + STATE_FIELDS[kind]) or typeof(state.first_attack_ready_frame) != TYPE_INT or state.first_attack_ready_frame != initial_ready_frame or not Contract.number_in_range(state.hp_after, 0.0, max_hp) or not state.damage_claims is Array or state.damage_claims.size() > MAX_DAMAGE_CLAIMS:
		return false
	if typeof(state.last_action_id) != TYPE_STRING or not _integer(state.consecutive_actions, 0, 2147483646) or (state.last_action_id.is_empty() != (state.consecutive_actions == 0)) or (not state.last_action_id.is_empty() and not action_ids(kind, true).has(state.last_action_id)):
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
			if not _integer(state.shell_remaining_frames, 0, authored.shell_frames) or not _integer(state.open_remaining_frames, 0, authored.open_frames) or not _integer(state.shell_cycle, 0, 2147483646) or not _integer(state.shell_shock_cycle, 0, state.shell_cycle) or typeof(state.shell_shock_used) != TYPE_BOOL or (state.shell_remaining_frames > 0 and state.open_remaining_frames > 0):
				return false
			if state.shell_shock_used:
				return state.shell_cycle > 0 and state.shell_shock_cycle == state.shell_cycle
			return state.shell_shock_cycle < state.shell_cycle or state.shell_cycle == 0
		"ruins_wraith":
			return Contract.number_in_range(state.windup_damage, 0.0, authored.windup_interrupt_damage) and state.windup_damage < authored.windup_interrupt_damage and _integer(state.stagger_remaining_frames, 0, authored.stagger_frames) and typeof(state.detonation_consumed) == TYPE_BOOL
		"rift_watcher":
			if typeof(state.death_debuff_reserved) != TYPE_BOOL or not state.healing_expenditure is Dictionary or state.healing_expenditure.size() > 8:
				return false
			for source: Variant in state.healing_expenditure:
				if typeof(source) != TYPE_STRING or source.is_empty() or not Contract.number_in_range(state.healing_expenditure[source], 0.0, 1000000.0):
					return false
			return true
		"void_hunter":
			return Contract.number_in_range(state.retreat_remaining_px, 0.0, authored.retreat_distance_px) and Contract.valid_point(state.retreat_direction, 1.0) and (state.retreat_remaining_px == 0.0 or is_equal_approx(_vector(state.retreat_direction).length(), 1.0))
		"void_spore": return typeof(state.burst_consumed) == TYPE_BOOL
		"shadow_lurker": return _integer(state.burrow_remaining_frames, 0, authored.burrow_cap_frames)
		"chrono_guard": return typeof(state.revival_used) == TYPE_BOOL and _integer(state.recovery_remaining_frames, 0, authored.revival_recovery_frames) and (state.revival_used or state.recovery_remaining_frames == 0) and (state.recovery_remaining_frames == 0 or state.hp_after == 1.0)
		"eternal_hound":
			if typeof(state.dormancy_used) != TYPE_BOOL or not _integer(state.dormancy_remaining_frames, 0, authored.dormancy_frames) or not Contract.number_in_range(state.sigil_hp, 0.0, authored.dormancy_sigil_hp) or not _valid_claims(state.sigil_claims):
				return false
			return (state.dormancy_used or (state.dormancy_remaining_frames == 0 and state.sigil_hp == 0.0 and state.sigil_claims.is_empty())) and (state.dormancy_remaining_frames == 0 or (state.hp_after == 1.0 and state.sigil_hp > 0.0))
		"forge_titan":
			return typeof(state.overheat_used) == TYPE_BOOL and typeof(state.explosion_reserved) == TYPE_BOOL and _integer(state.overheat_remaining_frames, 0, authored.overheat_frames) and (state.overheat_used or (state.overheat_remaining_frames == 0 and not state.explosion_reserved)) and (not state.explosion_reserved or state.overheat_remaining_frames == 0)
		"chaos_amalgam":
			return typeof(state.form_id) == TYPE_STRING and authored.form_ids.has(state.form_id) and _integer(state.form_elapsed_frames, 0, 2147483646) and _integer(state.switch_remaining_frames, 0, authored.switch_recovery_frames)
	return true


static func accept_damage(kind: String, authored: Dictionary, state: Dictionary, action: Dictionary, fact: Dictionary, max_hp: float) -> Dictionary:
	var claim := str(fact.fact_id).sha256_text()
	if state.damage_claims.has(claim) or state.damage_claims.size() >= MAX_DAMAGE_CLAIMS:
		return {"ok": false}
	var next := state.duplicate(true)
	next.damage_claims.append(claim)
	next.hp_after = float(fact.hp_after)
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
	if kind == "forge_titan" and not cancel_action and not next.overheat_used and next.hp_after / max_hp < float(authored.overheat_hp_threshold):
		next.overheat_used = true
		next.overheat_remaining_frames = authored.overheat_frames
	return {"ok": true, "state": next, "cancel_action": cancel_action}


static func recovery_frame_claim(kind: String, frame: int) -> String:
	return ("enemy_lethal_recovery:%s:%d" % [kind, frame]).sha256_text()


static func advance(kind: String, authored: Dictionary, state: Dictionary, before_action: Dictionary, after_action: Dictionary, max_hp: float, action_paused: bool, move_speed: float) -> Dictionary:
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
		"void_hunter":
			if not action_paused:
				next.retreat_remaining_px = maxf(0.0, next.retreat_remaining_px - move_speed / 60.0)
			if before_action.phase == "ACTIVE" and after_action.phase == "RECOVERY" and before_action.action_id == "void_hunter.claw_pair":
				next.retreat_remaining_px = float(authored.retreat_distance_px)
				var direction := -_vector(before_action.committed_aim)
				next.retreat_direction = {"x": direction.x, "y": direction.y}
		"void_spore":
			if before_action.phase == "ACTIVE" and after_action.phase == "RECOVERY" and before_action.action_id == "void_spore.spore_burst" and not next.burst_consumed:
				next.burst_consumed = true
				requests.append({"kind": "consume_actor", "attack_generation": before_action.geometry_generations[0], "hit_index": 63})
		"shadow_lurker":
			if not action_paused and next.burrow_remaining_frames > 0:
				next.burrow_remaining_frames -= 1
		"chrono_guard":
			if next.recovery_remaining_frames > 0 and not next.damage_claims.has(recovery_frame_claim(kind, int(after_action.last_runtime_frame))):
				next.recovery_remaining_frames -= 1
				if next.recovery_remaining_frames == 0:
					next.hp_after = minf(max_hp, float(authored.revival_hp))
					requests.append({"kind": "restore_hp", "amount": next.hp_after})
		"eternal_hound":
			if next.dormancy_remaining_frames > 0 and not next.damage_claims.has(recovery_frame_claim(kind, int(after_action.last_runtime_frame))):
				next.dormancy_remaining_frames -= 1
				if next.dormancy_remaining_frames == 0:
					next.sigil_hp = 0.0
					next.hp_after = minf(max_hp, float(authored.revival_hp))
					requests.append({"kind": "restore_hp", "amount": next.hp_after})
		"forge_titan":
			if next.overheat_remaining_frames > 0:
				next.overheat_remaining_frames -= 1
				if next.overheat_remaining_frames == 0 and not next.explosion_reserved:
					next.explosion_reserved = true
					requests.append({"kind": "warned_explosion", "parameters": {"warning_frames": int(authored.explosion_warning_frames), "damage": float(authored.explosion_damage), "radius": float(authored.explosion_radius_px)}})
		"chaos_amalgam":
			if next.switch_remaining_frames > 0:
				if not action_paused:
					next.switch_remaining_frames -= 1
			else:
				next.form_elapsed_frames = mini(2147483646, int(next.form_elapsed_frames) + 1)
				var cycle: int = authored.low_hp_form_cycle_frames if next.hp_after / max_hp < float(authored.low_hp_threshold) else authored.form_cycle_frames
				if next.form_elapsed_frames >= cycle and after_action.phase == "IDLE" and not action_paused:
					next.form_id = authored.form_ids[(authored.form_ids.find(next.form_id) + 1) % authored.form_ids.size()]
					next.form_elapsed_frames = 0
					next.switch_remaining_frames = authored.switch_recovery_frames
	return {"state": next, "requests": requests}


static func action_available(kind: String, state: Dictionary, action_id: String) -> bool:
	if kind == "shattered_sentinel":
		return state.retreat_remaining_frames == 0
	if kind == "ruins_wraith":
		return state.stagger_remaining_frames == 0 and not state.detonation_consumed and not action_id.ends_with(".spirit_split")
	if kind == "stone_shell_strider" and action_id.ends_with(".shell_shock"):
		return state.shell_remaining_frames > 0 and not state.shell_shock_used
	if kind == "void_hunter":
		return state.retreat_remaining_px == 0.0
	if kind == "void_spore":
		return not state.burst_consumed and not action_id.ends_with(".spore_split")
	if kind == "chrono_guard":
		return state.recovery_remaining_frames == 0
	if kind == "eternal_hound":
		return state.dormancy_remaining_frames == 0
	if kind == "chaos_amalgam":
		if state.switch_remaining_frames > 0:
			return false
		var suffix := action_id.get_slice(".", 1)
		return suffix == "chaos_outburst" or suffix in {"red": ["rage_combo", "flame_charge"], "blue": ["frost_wave", "ice_spikes"], "void": ["void_pull", "void_pulse"]}.get(state.form_id, [])
	return true


static func action_started(kind: String, state: Dictionary, action_id: String) -> Dictionary:
	var next := state.duplicate(true)
	next.consecutive_actions = int(next.consecutive_actions) + 1 if next.last_action_id == action_id else 1
	next.last_action_id = action_id
	if kind == "stone_shell_strider" and action_id.ends_with(".shell_shock"):
		next.shell_shock_used = true
		next.shell_shock_cycle = next.shell_cycle
	if kind == "ruins_wraith" and action_id.ends_with(".spirit_detonation"):
		next.windup_damage = 0.0
	if kind == "shadow_lurker" and action_id.ends_with(".shadow_ambush"):
		next.burrow_remaining_frames = 0
	return next


static func damage_taken_multiplier(kind: String, authored: Dictionary, state: Dictionary) -> float:
	if kind == "stone_shell_strider":
		if state.shell_remaining_frames > 0:
			return float(authored.shell_damage_multiplier)
		if state.open_remaining_frames > 0:
			return float(authored.open_damage_multiplier)
	if kind == "shadow_lurker" and state.burrow_remaining_frames > 0:
		return float(authored.ground_damage_multiplier)
	if kind == "eternal_hound" and state.dormancy_remaining_frames > 0:
		return 0.0
	return 1.0


static func nonattacking(state: Dictionary) -> bool:
	return int(state.get("recovery_remaining_frames", 0)) > 0 or int(state.get("dormancy_remaining_frames", 0)) > 0 or int(state.get("switch_remaining_frames", 0)) > 0


static func _valid_claims(value: Variant) -> bool:
	if not value is Array or value.size() > MAX_DAMAGE_CLAIMS:
		return false
	var seen: Dictionary = {}
	for claim: Variant in value:
		if typeof(claim) != TYPE_STRING or claim.length() != 64 or not claim.is_valid_hex_number(false) or seen.has(claim):
			return false
		seen[claim] = true
	return true


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) == TYPE_INT and Contract.integer_in_range(value, minimum, maximum)


static func _vector(value: Dictionary) -> Vector2:
	return Vector2(float(value.x), float(value.y))
