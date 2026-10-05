class_name LaunchEliteTeleportRuntime
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Parameters := preload("res://scripts/enemies/launch/elite_affix_definition.gd")
const FIELDS := ["elapsed_frames", "phase", "remaining_frames", "reservations"]
const RECEIPT_FIELDS := ["sequence", "start_elapsed_frame", "start_runtime_frame", "origin", "landing", "outcome", "arrival_runtime_frame"]
const MAX_RESERVATIONS := 4096


static func initial_state() -> Dictionary:
	return {"elapsed_frames": 0, "phase": "IDLE", "remaining_frames": 0, "reservations": []}


static func reservation_due(state: Dictionary) -> bool:
	return not state.is_empty() and state.reservations.size() < MAX_RESERVATIONS and (int(state.elapsed_frames) + 1) % int(Parameters.PARAMETERS.teleporting.interval_frames) == 0


static func blocks_actions(state: Dictionary) -> bool:
	return not state.is_empty() and (reservation_due(state) or state.phase == "DEPARTURE" or (state.phase == "ARRIVAL" and int(state.remaining_frames) > 1))


static func candidate_offsets(identity: Dictionary, sequence: int) -> Array[Vector2]:
	var digest := JSON.stringify([identity.run_id, identity.hostile_source_id, identity.seed, sequence], "", false).sha256_text()
	var angle_offset: int = digest.substr(0, 2).hex_to_int() % 8
	var distance_offset: int = digest.substr(2, 2).hex_to_int() % 4
	var result: Array[Vector2] = []
	var distances := [48.0, 56.0, 64.0, 80.0]
	for distance_index: int in range(4):
		for angle_index: int in range(8):
			var direction := Vector2.RIGHT.rotated((angle_index + angle_offset) * TAU / 8.0)
			result.append(direction * float(distances[(distance_index + distance_offset) % 4]))
	return result


static func advance(state: Dictionary, frame: int, paused: bool, observation: Dictionary) -> Dictionary:
	var next := state.duplicate(true)
	var relocation := {}
	if paused:
		return {"state": next, "relocation": relocation}
	next.elapsed_frames += 1
	var parameters: Dictionary = Parameters.PARAMETERS.teleporting
	if int(next.elapsed_frames) % int(parameters.interval_frames) == 0 and next.reservations.size() < MAX_RESERVATIONS:
		var skipped: bool = observation.landing_position.is_empty()
		next.reservations.append({"sequence": next.reservations.size() + 1, "start_elapsed_frame": int(next.elapsed_frames), "start_runtime_frame": frame, "origin": observation.source_position.duplicate(true), "landing": observation.landing_position.duplicate(true), "outcome": "SKIPPED" if skipped else "RESERVED", "arrival_runtime_frame": -1})
		if not skipped:
			next.phase = "DEPARTURE"
			next.remaining_frames = int(parameters.departure_warning_frames)
	elif next.phase == "DEPARTURE":
		next.remaining_frames -= 1
		if int(next.remaining_frames) == 0:
			var receipt: Dictionary = next.reservations.back()
			receipt.outcome = "LANDED" if observation.arrival_allowed else "BLOCKED"
			receipt.arrival_runtime_frame = frame
			next.phase = "ARRIVAL"
			next.remaining_frames = int(parameters.arrival_recovery_frames)
			if observation.arrival_allowed:
				relocation = receipt.landing.duplicate(true)
	elif next.phase == "ARRIVAL":
		next.remaining_frames -= 1
		if int(next.remaining_frames) == 0:
			next.phase = "IDLE"
	return {"state": next, "relocation": relocation}


static func cancel(state: Dictionary) -> void:
	if state.is_empty():
		return
	state.phase = "IDLE"
	state.remaining_frames = 0
	if not state.reservations.is_empty() and state.reservations.back().outcome == "RESERVED":
		state.reservations.back().outcome = "CANCELLED"


static func valid_observation(value: Dictionary) -> bool:
	return Contract.exact_fields(value, ["source_position", "landing_position", "arrival_allowed"]) and Contract.valid_point(value.source_position) and value.landing_position is Dictionary and (value.landing_position.is_empty() or Contract.valid_point(value.landing_position)) and typeof(value.arrival_allowed) == TYPE_BOOL


static func can_restore(state: Dictionary, identity: Dictionary, runtime_frame: int, terminal: bool) -> bool:
	var origin: int = int(identity.runtime_frame)
	var parameters: Dictionary = Parameters.PARAMETERS.teleporting
	if not Contract.exact_fields(state, FIELDS) or not Contract.integer_in_range(state.elapsed_frames, 0, runtime_frame - origin) or not state.reservations is Array or state.reservations.size() > MAX_RESERVATIONS or not state.phase is String or state.phase not in ["IDLE", "DEPARTURE", "ARRIVAL"] or not Contract.integer_in_range(state.remaining_frames, 0, 30):
		return false
	if state.reservations.size() != mini(MAX_RESERVATIONS, int(state.elapsed_frames) / int(parameters.interval_frames)):
		return false
	var previous_start := origin
	for index: int in range(state.reservations.size()):
		var receipt: Variant = state.reservations[index]
		var elapsed: int = (index + 1) * int(parameters.interval_frames)
		if not receipt is Dictionary or not Contract.exact_fields(receipt, RECEIPT_FIELDS) or not Contract.integer_in_range(receipt.sequence, index + 1, index + 1) or not Contract.integer_in_range(receipt.start_elapsed_frame, elapsed, elapsed) or not Contract.integer_in_range(receipt.start_runtime_frame, maxi(origin + elapsed, previous_start + int(parameters.interval_frames)), runtime_frame) or not Contract.valid_point(receipt.origin) or not receipt.landing is Dictionary or not receipt.outcome is String or receipt.outcome not in ["RESERVED", "LANDED", "BLOCKED", "SKIPPED", "CANCELLED"] or not Contract.integer_in_range(receipt.arrival_runtime_frame, -1, runtime_frame):
			return false
		previous_start = int(receipt.start_runtime_frame)
		if receipt.outcome == "SKIPPED":
			if not receipt.landing.is_empty() or receipt.arrival_runtime_frame != -1:
				return false
			continue
		if not Contract.valid_point(receipt.landing) or not _authored_offset(identity, index + 1, receipt.origin, receipt.landing):
			return false
		if receipt.outcome in ["RESERVED", "CANCELLED"]:
			if receipt.arrival_runtime_frame != -1 or index != state.reservations.size() - 1 or (receipt.outcome == "CANCELLED" and not terminal) or (receipt.outcome == "RESERVED" and int(state.elapsed_frames) >= elapsed + int(parameters.departure_warning_frames)):
				return false
		elif int(state.elapsed_frames) < elapsed + int(parameters.departure_warning_frames) or int(receipt.arrival_runtime_frame) < int(receipt.start_runtime_frame) + int(parameters.departure_warning_frames):
			return false
	var phase := "IDLE"
	var remaining := 0
	if not terminal and not state.reservations.is_empty():
		var latest: Dictionary = state.reservations.back()
		var age: int = int(state.elapsed_frames) - int(latest.start_elapsed_frame)
		if latest.outcome == "RESERVED":
			phase = "DEPARTURE"
			remaining = int(parameters.departure_warning_frames) - age
		elif latest.outcome in ["LANDED", "BLOCKED"] and age < int(parameters.departure_warning_frames) + int(parameters.arrival_recovery_frames):
			phase = "ARRIVAL"
			remaining = int(parameters.departure_warning_frames) + int(parameters.arrival_recovery_frames) - age
	return state.phase == phase and int(state.remaining_frames) == remaining


static func _authored_offset(identity: Dictionary, sequence: int, origin: Dictionary, landing: Dictionary) -> bool:
	var displacement := Vector2(float(landing.x) - float(origin.x), float(landing.y) - float(origin.y))
	for candidate: Vector2 in candidate_offsets(identity, sequence):
		if displacement.is_equal_approx(candidate):
			return true
	return false
