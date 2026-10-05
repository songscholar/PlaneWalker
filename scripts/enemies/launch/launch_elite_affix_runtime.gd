class_name LaunchEliteAffixRuntime
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Definition := preload("res://scripts/enemies/launch/elite_affix_definition.gd")
const Identity := preload("res://scripts/enemies/launch/launch_enemy_runtime.gd")
const Rules := preload("res://scripts/enemies/launch/elite_affix_rules.gd")
const Teleport := preload("res://scripts/enemies/launch/launch_elite_teleport_runtime.gd")
const Chaining := preload("res://scripts/enemies/launch/launch_elite_chaining_runtime.gd")
const Mirroring := preload("res://scripts/enemies/launch/launch_elite_mirroring_runtime.gd")
const CONFIGURATION_FIELDS := ["ids", "floor_index", "pending_ids", "damage_taken_multiplier", "knockback_resistance", "native_revision"]
const FIELDS := ["schema_version", "configuration_digest", "identity", "runtime_frame", "terminal", "regeneration"]
const ANCHORED_RUNTIME_FIELDS := ["schema_version", "configuration_digest", "identity", "runtime_frame", "terminal", "regeneration", "anchored"]
const ANCHORED_FIELDS := ["elapsed_frames", "control_count", "poise", "last_control_frame", "last_threshold_elapsed_frame", "recovery_remaining_frames"]
const REGENERATION_FIELDS := ["elapsed_frames", "healed_total", "interrupted_through_frame", "last_heal_frame"]
const NULLIFIED_RUNTIME_FIELDS := ["schema_version", "configuration_digest", "identity", "runtime_frame", "terminal", "regeneration", "anchored", "nullified"]
const NULLIFIED_FIELDS := ["sources", "stop_claims"]
const NULLIFIED_SOURCE_FIELDS := ["id", "applied_frame", "delay_through_frame", "vulnerability_through_frame"]
const MAX_NULLIFIED_CLAIMS := 4096
const MAX_NULLIFIED_SOURCES := 64
const NULLIFIED_DAMAGE_BONUS := 0.20
const SHIELDED_RUNTIME_FIELDS := ["schema_version", "configuration_digest", "identity", "runtime_frame", "terminal", "regeneration", "anchored", "nullified", "shielded"]
const SHIELD_FIELDS := ["current_pool", "first_break_frame", "last_break_frame", "regeneration_used", "regenerated_frame", "damage_claims"]
const SHIELD_CLAIM_FIELDS := ["fact_id", "runtime_frame", "amount", "absorbed", "epoch"]
const MAX_SHIELD_CLAIMS := 4096
const SHIELD_DAMAGE_BONUS := 0.20
const TELEPORTING_RUNTIME_FIELDS := ["schema_version", "configuration_digest", "identity", "runtime_frame", "terminal", "regeneration", "anchored", "nullified", "shielded", "teleporting"]
const CHAINING_RUNTIME_FIELDS := ["schema_version", "configuration_digest", "identity", "runtime_frame", "terminal", "regeneration", "anchored", "nullified", "shielded", "teleporting", "chaining"]
const MIRRORING_RUNTIME_FIELDS := ["schema_version", "configuration_digest", "identity", "runtime_frame", "terminal", "regeneration", "anchored", "nullified", "shielded", "teleporting", "chaining", "mirroring"]

var _configuration: Dictionary = {}
var _max_hp := 0.0
var _state: Dictionary = {}


func configure(configuration: Dictionary, identity: Dictionary, max_hp: float) -> bool:
	if not _state.is_empty() or not _valid_configuration(configuration) or not Contract.exact_fields(identity, Identity.IDENTITY_FIELDS) or not Contract.number_in_range(max_hp, 1.0, 1000000.0) or not Contract.integer_in_range(identity.runtime_frame, 0, Contract.MAX_FRAME) or not Contract.integer_in_range(identity.seed, -2147483648, 2147483647) or not Contract.integer_in_range(identity.next_generation_floor, 1, 2147483646) or not _stable_identity(identity.run_id) or not _stable_identity(identity.hostile_source_id):
		return false
	_configuration = configuration.duplicate(true)
	_max_hp = max_hp
	_state = {"schema_version": 1, "configuration_digest": JSON.stringify({"configuration": _configuration, "max_hp": _max_hp}, "", true, true).sha256_text(), "identity": identity.duplicate(true), "runtime_frame": identity.runtime_frame, "terminal": false, "regeneration": {}}
	if configuration.native_revision >= 3:
		_state.schema_version = 2
		_state["anchored"] = {"elapsed_frames": 0, "control_count": 0, "poise": 0, "last_control_frame": -1, "last_threshold_elapsed_frame": -1, "recovery_remaining_frames": 0} if configuration.ids.has("anchored") else {}
	if configuration.native_revision >= 4:
		_state.schema_version = 3
		_state["nullified"] = {"sources": [], "stop_claims": []} if configuration.ids.has("nullified") else {}
	if configuration.native_revision >= 5:
		_state.schema_version = 4
		_state["shielded"] = {"current_pool": _shield_maximum(), "first_break_frame": -1, "last_break_frame": -1, "regeneration_used": false, "regenerated_frame": -1, "damage_claims": []} if configuration.ids.has("shielded") else {}
	if configuration.native_revision >= 6:
		_state.schema_version = 5
		_state["teleporting"] = Teleport.initial_state() if configuration.ids.has("teleporting") else {}
	if configuration.native_revision >= 8:
		_state.schema_version = 6
		_state["chaining"] = Chaining.initial_state() if configuration.ids.has("chaining") else {}
	if configuration.native_revision >= 9:
		_state.schema_version = 7
		_state["mirroring"] = Mirroring.initial_state() if configuration.ids.has("mirroring") else {}
	if configuration.ids.has("regenerating"):
		_state.regeneration = {"elapsed_frames": 0, "healed_total": 0.0, "interrupted_through_frame": int(identity.runtime_frame), "last_heal_frame": -1}
	return true


static func _valid_configuration(value: Dictionary) -> bool:
	if not Contract.exact_fields(value, CONFIGURATION_FIELDS) or not Contract.integer_in_range(value.native_revision, 2, 9) or not Contract.integer_in_range(value.floor_index, 1, 5) or not value.ids is Array or value.ids.is_empty() or value.ids.size() > 2 or not value.pending_ids is Array:
		return false
	var seen: Array = []
	var pending: Array = []
	var previous := ""
	for id: Variant in value.ids:
		if not id is String or not Rules.MIN_FLOORS.has(id) or id <= previous or int(value.floor_index) < int(Rules.MIN_FLOORS[id]):
			return false
		for other: String in seen:
			if Rules.EXCLUSIONS[id].has(other) or Rules.EXCLUSIONS[other].has(id):
				return false
		seen.append(id)
		previous = id
		if id not in ["frenzy", "fortified", "regenerating"] and not (value.native_revision >= 3 and id == "anchored") and not (value.native_revision >= 4 and id == "nullified") and not (value.native_revision >= 5 and id == "shielded") and not (value.native_revision >= 6 and id == "teleporting") and not (value.native_revision >= 8 and id == "chaining") and not (value.native_revision >= 9 and id == "mirroring"):
			pending.append(id)
	return value.pending_ids == pending and Contract.number_in_range(value.damage_taken_multiplier, 1.2 if seen.has("frenzy") else 1.0, 1.2 if seen.has("frenzy") else 1.0) and Contract.number_in_range(value.knockback_resistance, 0.2 if seen.has("fortified") else 0.0, 0.2 if seen.has("fortified") else 0.0)


static func _stable_identity(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty() and value.length() <= 128 and value == value.strip_edges() and not value.contains("\n") and not value.contains("\r")


func advance_frame(frame: int, current_hp: float, dead: bool, paused: bool, healing_multiplier: float, teleport_observation: Dictionary = {}, source_position: Dictionary = {}) -> Dictionary:
	if _state.is_empty() or _state.terminal or frame != int(_state.runtime_frame) + 1 or not Contract.number_in_range(current_hp, 0.0, _max_hp) or not Contract.number_in_range(healing_multiplier, 0.0, 10.0):
		return {"ok": false}
	if is_teleporting() and not dead and not Teleport.valid_observation(teleport_observation):
		return {"ok": false}
	if is_mirroring() and not dead and not Contract.valid_point(source_position):
		return {"ok": false}
	if not pending_chaining_grants().is_empty():
		return {"ok": false}
	_state.runtime_frame = frame
	var healed := 0.0
	var teleport_relocation := {}
	if dead:
		_state.terminal = true
		if not _state.get("nullified", {}).is_empty():
			_state.nullified.sources.clear()
		if is_shielded():
			_state.shielded.current_pool = 0.0
		Teleport.cancel(_state.get("teleporting", {}))
	elif not paused:
		if not _state.get("anchored", {}).is_empty():
			_state.anchored.elapsed_frames += 1
			_state.anchored.recovery_remaining_frames = maxi(0, int(_state.anchored.recovery_remaining_frames) - 1)
	if not dead and not paused and not _state.regeneration.is_empty():
		var regeneration: Dictionary = _state.regeneration
		var parameters: Dictionary = Definition.PARAMETERS.regenerating
		regeneration.elapsed_frames += 1
		if int(regeneration.elapsed_frames) % int(parameters.interval_frames) == 0 and frame > int(regeneration.interrupted_through_frame):
			var available := maxf(0.0, _max_hp * float(parameters.total_heal_fraction_cap) - float(regeneration.healed_total))
			healed = minf(_max_hp - current_hp, minf(available, _max_hp * float(parameters.heal_fraction) * healing_multiplier))
			if healed < 0.000001:
				healed = 0.0
			if healed > 0.0:
				regeneration.healed_total = minf(_max_hp * float(parameters.total_heal_fraction_cap), float(regeneration.healed_total) + healed)
				if is_equal_approx(float(regeneration.healed_total), _max_hp * float(parameters.total_heal_fraction_cap)):
					regeneration.healed_total = _max_hp * float(parameters.total_heal_fraction_cap)
				regeneration.last_heal_frame = frame
	if not _state.get("nullified", {}).is_empty():
		_state.nullified.sources = _state.nullified.sources.filter(func(source: Dictionary): return int(source.vulnerability_through_frame) >= frame)
	if not dead and is_shielded() and not _state.shielded.regeneration_used and int(_state.shielded.first_break_frame) >= 0 and frame >= int(_state.shielded.first_break_frame) + int(Definition.PARAMETERS.shielded.regeneration_delay_frames):
		_state.shielded.current_pool = _shield_maximum()
		_state.shielded.regeneration_used = true
		_state.shielded.regenerated_frame = frame
	if not dead and is_teleporting():
		var advanced := Teleport.advance(_state.teleporting, frame, paused, teleport_observation)
		_state.teleporting = advanced.state
		teleport_relocation = advanced.relocation
	if not dead and is_mirroring():
		_state.mirroring = Mirroring.advance(_state.mirroring, frame, paused, source_position)
	return {"ok": true, "healed_amount": healed, "hp_after": current_hp + healed, "teleport_relocation": teleport_relocation}


func is_mirroring() -> bool:
	return not _state.get("mirroring", {}).is_empty()


func mirroring_phase() -> String:
	if not is_mirroring():
		return "ABSENT"
	if _state.terminal:
		return "TERMINAL"
	if _state.mirroring.reservations.is_empty():
		return "READY"
	var latest: Dictionary = _state.mirroring.reservations.back()
	return "SCHEDULED" if int(_state.runtime_frame) < int(latest.runtime_frame) + int(Definition.PARAMETERS.mirroring.spawn_warning_frames) else "COOLDOWN"


func is_teleporting() -> bool:
	return not _state.get("teleporting", {}).is_empty()


func teleport_blocks_actions() -> bool:
	return not _state.is_empty() and not _state.terminal and Teleport.blocks_actions(_state.get("teleporting", {}))


func teleport_reservation_due() -> bool:
	return not _state.is_empty() and not _state.terminal and Teleport.reservation_due(_state.get("teleporting", {}))


func teleport_candidate_offsets() -> Array[Vector2]:
	return Teleport.candidate_offsets(_state.identity, _state.teleporting.reservations.size() + 1) if is_teleporting() else []


func displacement_multiplier() -> float:
	return float(Definition.PARAMETERS.anchored.displacement_multiplier) if not _state.get("anchored", {}).is_empty() else 1.0


func is_anchor_recovering() -> bool:
	return not _state.get("anchored", {}).is_empty() and not _state.terminal and int(_state.anchored.recovery_remaining_frames) > 0


func is_nullified() -> bool:
	return not _state.get("nullified", {}).is_empty()


func accept_nullified_stop(source_id: String) -> bool:
	if not is_nullified() or _state.terminal or not _stable_source(source_id) or _state.nullified.stop_claims.has(source_id) or _state.nullified.stop_claims.size() >= MAX_NULLIFIED_CLAIMS or _state.nullified.sources.size() >= MAX_NULLIFIED_SOURCES:
		return false
	var parameters: Dictionary = Definition.PARAMETERS.nullified
	var delay_through: int = int(_state.runtime_frame) + int(parameters.stop_delay_frames)
	var vulnerability_through: int = delay_through + int(parameters.stop_vulnerability_frames)
	if vulnerability_through > Contract.MAX_FRAME:
		return false
	_state.nullified.stop_claims.append(source_id)
	_state.nullified.stop_claims.sort()
	_state.nullified.sources.append({"id": source_id, "applied_frame": int(_state.runtime_frame), "delay_through_frame": delay_through, "vulnerability_through_frame": vulnerability_through})
	_state.nullified.sources.sort_custom(func(left: Dictionary, right: Dictionary): return left.id < right.id)
	return true


func clear_nullified_stop(source_id: String) -> bool:
	if not is_nullified():
		return false
	for index: int in range(_state.nullified.sources.size()):
		if _state.nullified.sources[index].id == source_id:
			_state.nullified.sources.remove_at(index)
			return true
	return false


func is_nullified_delayed(frame: int = -1) -> bool:
	if not is_nullified() or _state.terminal:
		return false
	var accepted_frame: int = int(_state.runtime_frame) if frame < 0 else frame
	for source: Dictionary in _state.nullified.sources:
		if accepted_frame <= int(source.delay_through_frame):
			return true
	return false


func nullified_damage_bonus() -> float:
	if not is_nullified() or _state.terminal:
		return 0.0
	for source: Dictionary in _state.nullified.sources:
		if int(_state.runtime_frame) > int(source.delay_through_frame) and int(_state.runtime_frame) <= int(source.vulnerability_through_frame):
			return NULLIFIED_DAMAGE_BONUS
	return 0.0


func rift_movement_floor() -> float:
	return float(Definition.PARAMETERS.nullified.rift_movement_floor) if is_nullified() else 0.40


func is_shielded() -> bool:
	return not _state.get("shielded", {}).is_empty()


func shield_damage_bonus() -> float:
	if not is_shielded() or _state.terminal or int(_state.shielded.last_break_frame) < 0:
		return 0.0
	return SHIELD_DAMAGE_BONUS if int(_state.runtime_frame) <= int(_state.shielded.last_break_frame) + int(Definition.PARAMETERS.shielded.break_exposure_frames) - 1 else 0.0


func prepare_shield_absorption(frame: int, fact_id: String, amount: float) -> Dictionary:
	if not is_shielded() or _state.terminal or frame not in [int(_state.runtime_frame), int(_state.runtime_frame) + 1] or fact_id.length() != 64 or not fact_id.is_valid_hex_number(false) or not Contract.number_in_range(amount, 0.000001, 1000000.0) or _state.shielded.damage_claims.size() >= MAX_SHIELD_CLAIMS:
		return {"ok": false}
	for claim: Dictionary in _state.shielded.damage_claims:
		if claim.fact_id == fact_id:
			return {"ok": false}
	if not _state.shielded.damage_claims.is_empty() and frame < int(_state.shielded.damage_claims.back().runtime_frame):
		return {"ok": false}
	var after := snapshot()
	var absorbed := minf(float(after.shielded.current_pool), amount)
	after.shielded.current_pool = maxf(0.0, float(after.shielded.current_pool) - absorbed)
	if absorbed > 0.0 and after.shielded.current_pool == 0.0:
		after.shielded.first_break_frame = frame if after.shielded.first_break_frame == -1 else after.shielded.first_break_frame
		after.shielded.last_break_frame = frame
	after.shielded.damage_claims.append({"fact_id": fact_id, "runtime_frame": frame, "amount": amount, "absorbed": absorbed, "epoch": 1 if after.shielded.regeneration_used else 0})
	return {"ok": true, "amount_after": amount - absorbed, "absorbed": absorbed, "receipt": {"before": snapshot(), "after": after}}


func _shield_maximum() -> float:
	return _max_hp * float(Definition.PARAMETERS.shielded.shield_fraction)


func accept_launch_control(frame: int) -> bool:
	if _state.is_empty() or _state.terminal or _state.get("anchored", {}).is_empty() or frame not in [int(_state.runtime_frame), int(_state.runtime_frame) + 1] or int(_state.anchored.control_count) >= Contract.MAX_FRAME:
		return false
	var anchored: Dictionary = _state.anchored
	var parameters: Dictionary = Definition.PARAMETERS.anchored
	anchored.control_count += 1
	anchored.poise += int(parameters.control_poise)
	anchored.last_control_frame = frame
	if int(anchored.poise) >= int(parameters.poise_threshold):
		anchored.poise -= int(parameters.poise_threshold)
		anchored.last_threshold_elapsed_frame = anchored.elapsed_frames
		anchored.recovery_remaining_frames = int(parameters.recovery_extension_frames)
	return true


func interrupt_regeneration(frame: int) -> bool:
	if _state.is_empty() or _state.terminal or _state.regeneration.is_empty() or frame not in [int(_state.runtime_frame), int(_state.runtime_frame) + 1] or frame > Contract.MAX_FRAME - int(Definition.PARAMETERS.regenerating.heavy_interrupt_frames):
		return false
	_state.regeneration.interrupted_through_frame = frame + int(Definition.PARAMETERS.regenerating.heavy_interrupt_frames)
	return true


func settle_regeneration_heal(frame: int, planned: float, actual: float, before: Dictionary) -> bool:
	if not can_restore_snapshot(before) or _state.regeneration.is_empty() or before.regeneration.is_empty() or frame != int(_state.runtime_frame) or int(before.runtime_frame) + 1 != frame or not Contract.number_in_range(planned, 0.000001, _max_hp) or not Contract.number_in_range(actual, 0.0, planned) or int(_state.regeneration.last_heal_frame) != frame or not is_equal_approx(float(_state.regeneration.healed_total), float(before.regeneration.healed_total) + planned):
		return false
	var cap := _max_hp * float(Definition.PARAMETERS.regenerating.total_heal_fraction_cap)
	_state.regeneration.healed_total = minf(cap, float(before.regeneration.healed_total) + actual)
	if is_equal_approx(float(_state.regeneration.healed_total), cap):
		_state.regeneration.healed_total = cap
	_state.regeneration.last_heal_frame = frame if actual > 0.0 else int(before.regeneration.last_heal_frame)
	return true


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func accept_chaining_player_damage(frame: int, fact_id: String, position: Dictionary) -> bool:
	return not _state.is_empty() and not _state.terminal and frame in [int(_state.runtime_frame), int(_state.runtime_frame) + 1] and Chaining.accept_damage(_state.get("chaining", {}), frame, fact_id, position)


func pending_chaining_grants() -> Array:
	return Chaining.pending_grants(_state.get("chaining", {}))


func chaining_phase() -> String:
	if _state.get("chaining", {}).is_empty():
		return "ABSENT"
	if _state.terminal:
		return "TERMINAL"
	if _state.chaining.grants.is_empty():
		return "READY"
	var elapsed: int = int(_state.runtime_frame) - int(_state.chaining.grants.back().trigger_frame)
	return "TRIGGERED" if elapsed < 16 else ("COOLDOWN" if elapsed < int(Definition.PARAMETERS.chaining.cooldown_frames) else "READY")


func settle_chaining_grant(frame: int, fact_id: String, recipients: Array) -> bool:
	return not _state.is_empty() and frame == int(_state.runtime_frame) + 1 and Chaining.settle_grant(_state.get("chaining", {}), frame, fact_id, recipients)


func cancel() -> void:
	if not _state.is_empty():
		_state.terminal = true
		Chaining.close_pending_on_retirement(_state.get("chaining", {}))
		if is_nullified():
			_state.nullified.sources.clear()
		if is_shielded():
			_state.shielded.current_pool = 0.0
		Teleport.cancel(_state.get("teleporting", {}))


func can_restore_snapshot(value: Dictionary) -> bool:
	var revision: int = int(_configuration.get("native_revision", 0))
	var fields: Array = MIRRORING_RUNTIME_FIELDS if revision >= 9 else (CHAINING_RUNTIME_FIELDS if revision >= 8 else (TELEPORTING_RUNTIME_FIELDS if revision >= 6 else (SHIELDED_RUNTIME_FIELDS if revision >= 5 else (NULLIFIED_RUNTIME_FIELDS if revision >= 4 else (ANCHORED_RUNTIME_FIELDS if revision >= 3 else FIELDS)))))
	if _state.is_empty() or not Contract.exact_fields(value, fields) or value.schema_version != _state.schema_version or typeof(value.schema_version) != TYPE_INT or value.configuration_digest != _state.configuration_digest or value.identity != _state.identity or not Contract.integer_in_range(value.runtime_frame, int(_state.identity.runtime_frame), Contract.MAX_FRAME) or not value.terminal is bool or not value.regeneration is Dictionary:
		return false
	if revision >= 3 and not _can_restore_anchored(value):
		return false
	if revision >= 4 and not _can_restore_nullified(value):
		return false
	if revision >= 5 and not _can_restore_shield(value):
		return false
	if revision >= 6 and (not value.teleporting is Dictionary or (_configuration.ids.has("teleporting") and not Teleport.can_restore(value.teleporting, _state.identity, int(value.runtime_frame), value.terminal)) or (not _configuration.ids.has("teleporting") and not value.teleporting.is_empty())):
		return false
	if revision >= 8 and (not value.chaining is Dictionary or (_configuration.ids.has("chaining") and not Chaining.can_restore(value.chaining, _state.identity, int(value.runtime_frame))) or (not _configuration.ids.has("chaining") and not value.chaining.is_empty())):
		return false
	if revision >= 9 and (not value.mirroring is Dictionary or (_configuration.ids.has("mirroring") and not Mirroring.can_restore(value.mirroring, _state.identity, int(value.runtime_frame))) or (not _configuration.ids.has("mirroring") and not value.mirroring.is_empty())):
		return false
	if not _configuration.ids.has("regenerating"):
		return value.regeneration.is_empty()
	var state: Dictionary = value.regeneration
	var origin := int(_state.identity.runtime_frame)
	var frame := int(value.runtime_frame)
	if not Contract.exact_fields(state, REGENERATION_FIELDS) or not Contract.integer_in_range(state.elapsed_frames, 0, frame - origin) or not Contract.number_in_range(state.healed_total, 0.0, _max_hp * float(Definition.PARAMETERS.regenerating.total_heal_fraction_cap)) or not Contract.integer_in_range(state.interrupted_through_frame, origin, mini(Contract.MAX_FRAME, frame + 1 + int(Definition.PARAMETERS.regenerating.heavy_interrupt_frames))) or not Contract.integer_in_range(state.last_heal_frame, -1, frame):
		return false
	if state.last_heal_frame != -1 and (state.last_heal_frame < origin + int(Definition.PARAMETERS.regenerating.interval_frames) or state.elapsed_frames < int(Definition.PARAMETERS.regenerating.interval_frames)):
		return false
	return (float(state.healed_total) == 0.0) == (state.last_heal_frame == -1)


func _can_restore_anchored(value: Dictionary) -> bool:
	if not value.anchored is Dictionary:
		return false
	if not _configuration.ids.has("anchored"):
		return value.anchored.is_empty()
	var anchored: Dictionary = value.anchored
	var origin := int(_state.identity.runtime_frame)
	var frame := int(value.runtime_frame)
	var parameters: Dictionary = Definition.PARAMETERS.anchored
	if not Contract.exact_fields(anchored, ANCHORED_FIELDS) or not Contract.integer_in_range(anchored.elapsed_frames, 0, frame - origin) or not Contract.integer_in_range(anchored.control_count, 0, Contract.MAX_FRAME) or not Contract.integer_in_range(anchored.poise, 0, int(parameters.poise_threshold) - 1) or not Contract.integer_in_range(anchored.last_control_frame, -1, mini(Contract.MAX_FRAME, frame + 1)) or not Contract.integer_in_range(anchored.last_threshold_elapsed_frame, -1, int(anchored.elapsed_frames)) or not Contract.integer_in_range(anchored.recovery_remaining_frames, 0, int(parameters.recovery_extension_frames)):
		return false
	if int(anchored.poise) != (int(anchored.control_count) * int(parameters.control_poise)) % int(parameters.poise_threshold) or (anchored.control_count == 0) != (anchored.last_control_frame == -1):
		return false
	if anchored.control_count == 0:
		return anchored.last_threshold_elapsed_frame == -1 and anchored.recovery_remaining_frames == 0
	if anchored.last_control_frame < origin:
		return false
	var threshold_reached: bool = int(anchored.control_count) * int(parameters.control_poise) >= int(parameters.poise_threshold)
	if threshold_reached != (anchored.last_threshold_elapsed_frame >= 0):
		return false
	var remaining: int = maxi(0, int(parameters.recovery_extension_frames) - (int(anchored.elapsed_frames) - int(anchored.last_threshold_elapsed_frame))) if threshold_reached else 0
	return anchored.recovery_remaining_frames == remaining


func _can_restore_nullified(value: Dictionary) -> bool:
	if not value.nullified is Dictionary:
		return false
	if not _configuration.ids.has("nullified"):
		return value.nullified.is_empty()
	var state: Dictionary = value.nullified
	if not Contract.exact_fields(state, NULLIFIED_FIELDS) or not state.stop_claims is Array or state.stop_claims.size() > MAX_NULLIFIED_CLAIMS or not state.sources is Array or state.sources.size() > MAX_NULLIFIED_SOURCES or (value.terminal and not state.sources.is_empty()):
		return false
	var previous := ""
	for claim: Variant in state.stop_claims:
		if not claim is String or not _stable_source(claim) or claim <= previous:
			return false
		previous = claim
	previous = ""
	var parameters: Dictionary = Definition.PARAMETERS.nullified
	for source: Variant in state.sources:
		if not source is Dictionary or not Contract.exact_fields(source, NULLIFIED_SOURCE_FIELDS) or not _stable_source(source.id) or source.id <= previous or not state.stop_claims.has(source.id) or not Contract.integer_in_range(source.applied_frame, int(_state.identity.runtime_frame), int(value.runtime_frame)):
			return false
		if not Contract.integer_in_range(source.delay_through_frame, int(source.applied_frame) + int(parameters.stop_delay_frames), int(source.applied_frame) + int(parameters.stop_delay_frames)) or not Contract.integer_in_range(source.vulnerability_through_frame, int(source.delay_through_frame) + int(parameters.stop_vulnerability_frames), int(source.delay_through_frame) + int(parameters.stop_vulnerability_frames)) or int(source.vulnerability_through_frame) < int(value.runtime_frame) or int(source.vulnerability_through_frame) > Contract.MAX_FRAME:
			return false
		previous = source.id
	return true


static func _stable_source(value: Variant) -> bool:
	return value is String and not value.is_empty() and value == value.strip_edges() and value.length() <= 64


func _can_restore_shield(value: Dictionary) -> bool:
	if not value.shielded is Dictionary:
		return false
	if not _configuration.ids.has("shielded"):
		return value.shielded.is_empty()
	var shield: Dictionary = value.shielded
	var frame := int(value.runtime_frame)
	var origin := int(_state.identity.runtime_frame)
	if not Contract.exact_fields(shield, SHIELD_FIELDS) or not Contract.number_in_range(shield.current_pool, 0.0, _shield_maximum()) or not Contract.integer_in_range(shield.first_break_frame, -1, frame + 1) or not Contract.integer_in_range(shield.last_break_frame, -1, frame + 1) or typeof(shield.regeneration_used) != TYPE_BOOL or not Contract.integer_in_range(shield.regenerated_frame, -1, frame) or not shield.damage_claims is Array or shield.damage_claims.size() > MAX_SHIELD_CLAIMS:
		return false
	var pool := _shield_maximum()
	var first_break := -1
	var last_break := -1
	var epoch := 0
	var previous_frame := origin
	var seen := {}
	for claim: Variant in shield.damage_claims:
		if not claim is Dictionary or not Contract.exact_fields(claim, SHIELD_CLAIM_FIELDS) or not claim.fact_id is String or claim.fact_id.length() != 64 or not claim.fact_id.is_valid_hex_number(false) or seen.has(claim.fact_id) or not Contract.integer_in_range(claim.runtime_frame, previous_frame, frame + 1) or not Contract.number_in_range(claim.amount, 0.000001, 1000000.0) or not Contract.integer_in_range(claim.epoch, epoch, 1) or not Contract.number_in_range(claim.absorbed, 0.0, _shield_maximum()):
			return false
		if int(claim.epoch) == 1:
			if not shield.regeneration_used or first_break < 0 or int(claim.runtime_frame) < int(shield.regenerated_frame):
				return false
			if epoch == 0:
				pool = _shield_maximum()
				epoch = 1
		elif shield.regeneration_used and int(claim.runtime_frame) > int(shield.regenerated_frame):
			return false
		var absorbed := minf(pool, float(claim.amount))
		if not is_equal_approx(float(claim.absorbed), absorbed):
			return false
		pool = maxf(0.0, pool - absorbed)
		if absorbed > 0.0 and pool == 0.0:
			first_break = int(claim.runtime_frame) if first_break == -1 else first_break
			last_break = int(claim.runtime_frame)
		seen[claim.fact_id] = true
		previous_frame = int(claim.runtime_frame)
	if shield.first_break_frame != first_break or shield.last_break_frame != last_break:
		return false
	var deadline: int = first_break + int(Definition.PARAMETERS.shielded.regeneration_delay_frames)
	if shield.regeneration_used:
		if first_break < origin or shield.regenerated_frame != deadline or int(shield.regenerated_frame) > frame:
			return false
		if epoch == 0:
			pool = _shield_maximum()
	elif shield.regenerated_frame != -1 or (first_break >= 0 and (frame > deadline or frame == deadline and not value.terminal)):
		return false
	return is_equal_approx(float(shield.current_pool), 0.0 if value.terminal else pool)


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	_state = value.duplicate(true)
	return true
