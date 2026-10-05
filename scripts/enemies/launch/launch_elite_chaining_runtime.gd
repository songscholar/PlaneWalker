extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Definition := preload("res://scripts/enemies/launch/elite_affix_definition.gd")
const FIELDS := ["damage_claims", "grants"]
const CLAIM_FIELDS := ["fact_id", "runtime_frame", "source_position"]
const GRANT_FIELDS := ["fact_id", "trigger_frame", "source_position", "settled_frame", "recipients"]
const RECIPIENT_FIELDS := ["id", "position"]
const MAX_CLAIMS := 4096


static func initial_state() -> Dictionary:
	return {"damage_claims": [], "grants": []}


static func accept_damage(state: Dictionary, frame: int, fact_id: String, position: Dictionary) -> bool:
	if state.is_empty() or state.damage_claims.size() >= MAX_CLAIMS or not Contract.integer_in_range(frame, 0, Contract.MAX_FRAME) or not _hash(fact_id) or not Contract.valid_point(position):
		return false
	for claim: Dictionary in state.damage_claims:
		if claim.fact_id == fact_id:
			return false
	if not state.damage_claims.is_empty() and frame < int(state.damage_claims.back().runtime_frame):
		return false
	state.damage_claims.append({"fact_id": fact_id, "runtime_frame": frame, "source_position": position.duplicate(true)})
	if state.grants.is_empty() or frame >= int(state.grants.back().trigger_frame) + int(Definition.PARAMETERS.chaining.cooldown_frames):
		state.grants.append({"fact_id": fact_id, "trigger_frame": frame, "source_position": position.duplicate(true), "settled_frame": -1, "recipients": []})
	return true


static func pending_grants(state: Dictionary) -> Array:
	return state.get("grants", []).filter(func(row: Dictionary): return int(row.settled_frame) == -1).duplicate(true)


static func close_pending_on_retirement(state: Dictionary) -> void:
	for grant: Dictionary in state.get("grants", []):
		if int(grant.settled_frame) == -1:
			grant.settled_frame = grant.trigger_frame
			grant.recipients = []


static func settle_grant(state: Dictionary, frame: int, fact_id: String, recipients: Array) -> bool:
	for grant: Dictionary in state.get("grants", []):
		if grant.fact_id == fact_id and grant.settled_frame == -1 and frame in [int(grant.trigger_frame), int(grant.trigger_frame) + 1] and _valid_recipients(recipients, grant.source_position):
			grant.settled_frame = frame
			grant.recipients = recipients.duplicate(true)
			return true
	return false


static func can_restore(value: Dictionary, identity: Dictionary, frame: int) -> bool:
	if not Contract.exact_fields(value, FIELDS) or not value.damage_claims is Array or value.damage_claims.size() > MAX_CLAIMS or not value.grants is Array or value.grants.size() > value.damage_claims.size():
		return false
	var seen := {}
	var expected: Array[Dictionary] = []
	var previous := int(identity.runtime_frame)
	var last_trigger := -1
	for claim: Variant in value.damage_claims:
		if not claim is Dictionary or not Contract.exact_fields(claim, CLAIM_FIELDS) or not _hash(claim.fact_id) or seen.has(claim.fact_id) or not Contract.integer_in_range(claim.runtime_frame, previous, mini(Contract.MAX_FRAME, frame + 1)) or not Contract.valid_point(claim.source_position):
			return false
		seen[claim.fact_id] = true
		previous = int(claim.runtime_frame)
		if last_trigger == -1 or int(claim.runtime_frame) >= last_trigger + int(Definition.PARAMETERS.chaining.cooldown_frames):
			expected.append(claim)
			last_trigger = int(claim.runtime_frame)
	if expected.size() != value.grants.size():
		return false
	for index: int in range(expected.size()):
		var grant: Variant = value.grants[index]
		var claim: Dictionary = expected[index]
		if not grant is Dictionary or not Contract.exact_fields(grant, GRANT_FIELDS) or grant.fact_id != claim.fact_id or grant.trigger_frame != claim.runtime_frame or grant.source_position != claim.source_position or not Contract.integer_in_range(grant.settled_frame, -1, mini(Contract.MAX_FRAME, frame + 1)) or not grant.recipients is Array or not _valid_recipients(grant.recipients, grant.source_position):
			return false
		if grant.settled_frame == -1:
			if not grant.recipients.is_empty() or int(grant.trigger_frame) < frame:
				return false
		elif int(grant.settled_frame) not in [int(grant.trigger_frame), int(grant.trigger_frame) + 1]:
			return false
		for recipient: Dictionary in grant.recipients:
			if recipient.id == identity.hostile_source_id:
				return false
	return true


static func _valid_recipients(rows: Array, source_position: Dictionary) -> bool:
	if rows.size() > int(Definition.PARAMETERS.chaining.recipient_count_cap):
		return false
	var seen := {}
	var origin := Vector2(float(source_position.x), float(source_position.y))
	var last_distance := -1.0
	var last_id := ""
	for row: Variant in rows:
		if not row is Dictionary or not Contract.exact_fields(row, RECIPIENT_FIELDS) or not _stable(row.id) or seen.has(row.id) or not Contract.valid_point(row.position):
			return false
		var distance := origin.distance_squared_to(Vector2(float(row.position.x), float(row.position.y)))
		if distance > pow(float(Definition.PARAMETERS.chaining.recipient_radius_px), 2.0) or distance < last_distance or (distance == last_distance and str(row.id) <= last_id):
			return false
		seen[row.id] = true
		last_distance = distance
		last_id = str(row.id)
	return true


static func control_id(fact_id: String) -> String:
	return "elite_chain:" + fact_id.substr(0, 40)


static func _hash(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and value.length() == 64 and value.is_valid_hex_number(false)


static func _stable(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty() and value.length() <= 128 and value == value.strip_edges() and not value.contains("\n") and not value.contains("\r")
