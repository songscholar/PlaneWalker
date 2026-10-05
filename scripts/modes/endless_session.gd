extends RefCounted

const Meta := preload("res://scripts/progression/meta_progression_catalog.gd")
const Request := preload("res://scripts/modes/boss_rush_catalog.gd")
const Seed := preload("res://scripts/core/seed_service.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const Build := preload("res://scripts/progression/run_build_state.gd")
const Rules := preload("res://scripts/community/local_run_record_rules.gd")
const MAX_SUMMARIES := 32
const FIELDS := ["schema_version", "mode_fingerprint", "sequence", "run_id", "request", "cycle_index", "status", "elapsed_frames", "cycle_frames", "continued", "completed_cycles", "carry_build_codec", "carry_player_codec"]


static func fingerprint(content: Dictionary) -> String:
	return Rules.canonical({"mode": "endless-v1", "summary_capacity": MAX_SUMMARIES, "hp_step": 0.15, "hp_cap": 3.0, "damage_step": 0.08, "damage_cap": 2.0, "content": content}).sha256_text()


static func empty(fingerprint_value: String) -> Dictionary:
	return {"schema_version": 1, "mode_fingerprint": fingerprint_value, "sequence": 0, "run_id": "", "request": {}, "cycle_index": 0, "status": "IDLE", "elapsed_frames": 0, "cycle_frames": 0, "continued": false, "completed_cycles": [], "carry_build_codec": "", "carry_player_codec": ""}


static func cycle_seed(seed: int, cycle: int) -> int:
	return Seed.derive_seed(seed, &"endless_cycle_v1", cycle) & 0x7fffffff


static func scaling(cycle: int) -> Dictionary:
	return {"hp_multiplier": minf(3.0, 1.0 + 0.15 * mini(cycle, 31)), "damage_multiplier": minf(2.0, 1.0 + 0.08 * mini(cycle, 31))} if cycle >= 0 and cycle <= Meta.MAX_VALUE else {}


static func valid(value: Variant, profile_id: String) -> bool:
	if not Meta.exact_fields(value, FIELDS) or value.schema_version != 1 or not Meta.fingerprint_valid(value.mode_fingerprint) or not Meta.bounded_int(value.sequence, 0, Meta.MAX_VALUE) or not Meta.bounded_int(value.cycle_index, 0, Meta.MAX_VALUE) or not Meta.bounded_int(value.elapsed_frames, 0, Meta.MAX_VALUE) or not Meta.bounded_int(value.cycle_frames, 0, int(value.elapsed_frames)) or not value.continued is bool or value.status not in ["IDLE", "STARTING", "ACTIVE", "CYCLE_CLEAR", "DEFEAT"] or not value.completed_cycles is Array or value.completed_cycles.size() > MAX_SUMMARIES or not value.carry_build_codec is String or not value.carry_player_codec is String or value.carry_build_codec.length() > 1048576 or value.carry_player_codec.length() > 1048576:
		return false
	if value.status == "IDLE":
		return Rules.same(value, empty(value.mode_fingerprint))
	if value.sequence < 1 or value.run_id != "endless-%s-%d" % [profile_id, int(value.sequence)] or not Request.valid_request(value.request):
		return false
	var total := 0
	var completed := int(value.cycle_index) + (1 if value.status == "CYCLE_CLEAR" else 0)
	var first_cycle := maxi(0, completed - MAX_SUMMARIES)
	for index: int in range(value.completed_cycles.size()):
		var row: Variant = value.completed_cycles[index]
		var cycle := first_cycle + index
		if not Meta.exact_fields(row, ["cycle_index", "seed", "frames", "final_floor_rooms", "native_digest"]) or row.cycle_index != cycle or row.seed != cycle_seed(int(value.request.seed), cycle) or not Meta.bounded_int(row.frames, 1, Meta.MAX_VALUE) or not Meta.bounded_int(row.final_floor_rooms, 1, 100) or not Meta.fingerprint_valid(row.native_digest):
			return false
		total += int(row.frames)
	if total > value.elapsed_frames:
		return false
	if value.completed_cycles.size() != mini(completed, MAX_SUMMARIES):
		return false
	if value.carry_build_codec.is_empty() != value.carry_player_codec.is_empty() or value.cycle_index > 0 and value.carry_build_codec.is_empty() or value.status == "CYCLE_CLEAR" and value.carry_build_codec.is_empty():
		return false
	if not value.carry_build_codec.is_empty():
		var build := Replay.decode_replay_json(value.carry_build_codec)
		var player := Replay.decode_replay_json(value.carry_player_codec)
		if not build.ok or not Build.new().can_restore_transaction_snapshot(build.replay) or build.replay.milestone != "LAUNCH" or not player.ok or not Replay.validate_full_player_reward_effect_state(player.replay) or player.replay.health.current_hp <= 0.0:
			return false
	return true


static func normalized(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	for field: String in ["schema_version", "sequence", "cycle_index", "elapsed_frames", "cycle_frames"]:
		result[field] = int(result[field])
	if not result.request.is_empty():
		result.request.seed = int(result.request.seed)
	for row: Dictionary in result.completed_cycles:
		for field: String in ["cycle_index", "seed", "frames", "final_floor_rooms"]:
			row[field] = int(row[field])
	return result
