extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Definition := preload("res://scripts/enemies/launch/elite_affix_definition.gd")
const FIELDS := ["elapsed_frames", "reservations"]
const RECEIPT_FIELDS := ["sequence", "elapsed_frame", "runtime_frame", "source_position"]
const MAX_RESERVATIONS := 4096


static func initial_state() -> Dictionary:
	return {"elapsed_frames": 0, "reservations": []}


static func candidate_positions(identity: Dictionary, receipt: Dictionary) -> Array[Vector2]:
	var digest := JSON.stringify([identity.run_id, identity.hostile_source_id, identity.seed, receipt.sequence], "", false).sha256_text()
	var angle_offset := digest.substr(0, 2).hex_to_int() % 8
	var distance_offset := digest.substr(2, 2).hex_to_int() % 4
	var distances := [24.0, 32.0, 40.0, 48.0]
	var origin := Vector2(float(receipt.source_position.x), float(receipt.source_position.y))
	var result: Array[Vector2] = []
	for distance: int in range(4):
		for angle: int in range(8):
			result.append(origin + Vector2.RIGHT.rotated((angle + angle_offset) * TAU / 8.0) * float(distances[(distance + distance_offset) % 4]))
	return result


static func authentic_position(identity: Dictionary, receipt: Dictionary, position: Dictionary) -> bool:
	var actual := Vector2(float(position.x), float(position.y))
	return candidate_positions(identity, receipt).any(func(candidate: Vector2): return candidate.is_equal_approx(actual))


static func advance(state: Dictionary, frame: int, paused: bool, position: Dictionary) -> Dictionary:
	var next := state.duplicate(true)
	if paused:
		return next
	next.elapsed_frames += 1
	if int(next.elapsed_frames) % int(Definition.PARAMETERS.mirroring.interval_frames) == 0 and next.reservations.size() < MAX_RESERVATIONS:
		next.reservations.append({"sequence": next.reservations.size() + 1, "elapsed_frame": int(next.elapsed_frames), "runtime_frame": frame, "source_position": position.duplicate(true)})
	return next


static func can_restore(value: Dictionary, identity: Dictionary, frame: int) -> bool:
	var origin := int(identity.runtime_frame)
	var interval := int(Definition.PARAMETERS.mirroring.interval_frames)
	if not Contract.exact_fields(value, FIELDS) or not Contract.integer_in_range(value.elapsed_frames, 0, frame - origin) or not value.reservations is Array or value.reservations.size() != mini(MAX_RESERVATIONS, int(value.elapsed_frames) / interval):
		return false
	var previous := origin
	for index: int in range(value.reservations.size()):
		var row: Variant = value.reservations[index]
		var elapsed := (index + 1) * interval
		if not row is Dictionary or not Contract.exact_fields(row, RECEIPT_FIELDS) or not Contract.integer_in_range(row.sequence, index + 1, index + 1) or not Contract.integer_in_range(row.elapsed_frame, elapsed, elapsed) or not Contract.integer_in_range(row.runtime_frame, maxi(origin + elapsed, previous + interval), frame) or not Contract.valid_point(row.source_position):
			return false
		previous = int(row.runtime_frame)
	return true
