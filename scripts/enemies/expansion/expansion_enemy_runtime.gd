class_name ExpansionEnemyRuntime
extends "res://scripts/enemies/launch/launch_enemy_runtime.gd"

const Expansion := preload("res://scripts/enemies/expansion/expansion_enemy_definition.gd")


func configure(definition: Dictionary, identity: Dictionary) -> Dictionary:
	_definition.clear()
	_state.clear()
	if not Contract.exact_fields(definition, Expansion.RUNTIME_FIELDS) or not Contract.exact_fields(identity, IDENTITY_FIELDS) or not Expansion.IDS.has(definition.get("id")) or definition.runtime_kind != definition.id or definition.actor_kind != "enemy" or not Contract.integer_in_range(identity.seed, -2147483648, 2147483647):
		return _failure("expansion_identity")
	var stats := DefinitionContract.numeric_fields(definition, {"max_hp": [1, 1000, false], "defense": [0, 100, false], "move_speed": [0, 240, false], "collision_radius_px": [1, 32, false]})
	var mechanisms := DefinitionContract.mechanisms(definition.mechanisms, Expansion.MECHANISM_RULES)
	var actions := DefinitionContract.actions(definition.actions, "enemy", definition.id + ".", 30, {})
	if not stats.ok or not mechanisms.ok or not actions.ok or mechanisms.value.kite_min_px > mechanisms.value.kite_max_px:
		return _failure("expansion_fields")
	var index: int = Expansion.IDS.find(definition.id)
	if actions.value.size() != Expansion.ACTION_IDS[index].size():
		return _failure("expansion_actions")
	for action_index: int in range(actions.value.size()):
		var action: Dictionary = actions.value[action_index]
		if action.id != Expansion.ACTION_IDS[index][action_index] or action.handler_id != Expansion.HANDLERS[index][action_index] or action.handler_id == "charge" and (action.geometry.size() != 1 or action.hit_schedule.size() != 1):
			return _failure("expansion_pattern")
	var action_identity := identity.duplicate(true)
	action_identity.erase("seed")
	var configured: Dictionary = _action.configure({"id": definition.id, "actor_kind": "enemy", "actions": actions.value}, action_identity)
	if not configured.ok:
		return configured
	var controlled: Dictionary = _control.configure({"run_id": identity.run_id, "hostile_source_id": identity.hostile_source_id, "runtime_frame": identity.runtime_frame})
	if not controlled.ok:
		return controlled
	_definition = definition.duplicate(true)
	_definition.merge(stats.value, true)
	_definition.actions = actions.value
	_definition.mechanisms = mechanisms.value
	var rng := Seeds.make_rng(int(identity.seed), StringName("expansion_first_attack_v1:%s" % identity.hostile_source_id))
	_state = {"schema_version": 1, "definition_digest": JSON.stringify(_definition, "", true, true).sha256_text(), "identity": identity.duplicate(true), "runtime_frame": int(identity.runtime_frame), "terminal": false, "mechanism_state": {"first_attack_ready_frame": int(identity.runtime_frame) + rng.randi_range(0, int(mechanisms.value.first_attack_stagger_frames)), "damage_claims": [], "hp_after": float(_definition.max_hp), "last_action_id": "", "consecutive_actions": 0}}
	return {"ok": true, "snapshot": snapshot()}


func can_restore_snapshot(value: Dictionary) -> bool:
	if _state.is_empty() or not Contract.exact_fields(value, STATE_FIELDS) or typeof(value.schema_version) != TYPE_INT or value.schema_version != 1 or value.definition_digest != _state.definition_digest or value.identity != _state.identity or not Contract.integer_in_range(value.runtime_frame, int(_state.identity.runtime_frame), Contract.MAX_FRAME * 1000) or typeof(value.terminal) != TYPE_BOOL or not value.mechanism_state is Dictionary:
		return false
	var mechanism: Dictionary = value.mechanism_state
	if not Contract.exact_fields(mechanism, Mechanisms.COMMON_FIELDS) or typeof(mechanism.first_attack_ready_frame) != TYPE_INT or mechanism.first_attack_ready_frame != _state.mechanism_state.first_attack_ready_frame or not Contract.number_in_range(mechanism.hp_after, 0.0, _definition.max_hp) or not mechanism.damage_claims is Array or mechanism.damage_claims.size() > Mechanisms.MAX_DAMAGE_CLAIMS or typeof(mechanism.last_action_id) != TYPE_STRING or not Contract.integer_in_range(mechanism.consecutive_actions, 0, 2147483646):
		return false
	if mechanism.last_action_id.is_empty() != (mechanism.consecutive_actions == 0) or not mechanism.last_action_id.is_empty() and not Expansion.ACTION_IDS[Expansion.IDS.find(_definition.id)].has(mechanism.last_action_id):
		return false
	var seen := {}
	for claim: Variant in mechanism.damage_claims:
		if not claim is String or claim.length() != 64 or not claim.is_valid_hex_number(false) or claim != claim.to_lower() or seen.has(claim):
			return false
		seen[claim] = true
	if not value.action is Dictionary or not value.control is Dictionary or not _action.can_restore_snapshot(value.action) or not _control.can_restore_snapshot(value.control):
		return false
	return value.action.last_runtime_frame == value.runtime_frame and value.control.runtime_frame == value.runtime_frame and value.control.terminal == value.terminal and (not value.terminal or value.action.phase == "IDLE")
