extends RefCounted

const Envelope := preload("res://scripts/save/save_envelope.gd")
const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Paths := preload("res://scripts/save/save_path_policy.gd")
const Lifetime := preload("res://scripts/events/event_modifier_lifetime.gd")
const MAX_ENTRIES := 1000
const MAX_OWNERS := 1000
const ENTRY_FIELDS := ["id", "profile_id", "run_id", "launch_sequence", "receipt_digest", "character_id", "weapon_id", "difficulty", "terminal_reason", "completed_floors", "completed_rooms", "run_time_ms", "score"]


static func board_id(binding: Dictionary, domain: String) -> String:
	return "board_" + canonical({"content_snapshot": binding, "save_domain": domain}).sha256_text().substr(0, 26)


static func record(source: Dictionary) -> Dictionary:
	var terminal: Dictionary = source.terminal
	var facts := Lifetime.validate_events(terminal.events)
	if not facts.ok or not Lifetime.history_matches_plan(terminal.events, terminal.floor_plan):
		return {}
	var receipt: Dictionary = source.receipt
	var config: Dictionary = terminal.config
	var floors: int = terminal.completed_floor_ids.size()
	var rooms: int = facts.context.room_facts.size()
	var identity := canonical({"profile_id": source.profile_id, "run_id": receipt.run_id, "receipt_digest": receipt.digest}).sha256_text()
	return {"id": "record_" + identity, "profile_id": source.profile_id, "run_id": receipt.run_id, "launch_sequence": int(receipt.sequence), "receipt_digest": receipt.digest, "character_id": config.character_id, "weapon_id": config.weapon_id, "difficulty": config.difficulty, "terminal_reason": receipt.terminal_reason, "completed_floors": floors, "completed_rooms": rooms, "run_time_ms": int(terminal.run_time_ms), "score": score(floors, rooms, receipt.terminal_reason)}


static func valid_board(value: Variant, binding: Dictionary, domain: String) -> bool:
	if not Catalog.exact_fields(value, ["schema_version", "content_snapshot", "save_domain", "entries", "watermarks"]) or value.schema_version != 1 or not same(value.content_snapshot, binding) or value.save_domain != domain or not value.entries is Array or value.entries.size() > MAX_ENTRIES or not value.watermarks is Dictionary or value.watermarks.size() > MAX_OWNERS:
		return false
	for owner: Variant in value.watermarks:
		var watermark: Variant = value.watermarks[owner]
		if not Paths.validate_id(owner).ok or not Catalog.exact_fields(watermark, ["launch_sequence", "run_id", "receipt_digest"]) or not Catalog.bounded_int(watermark.launch_sequence, 1, Catalog.MAX_VALUE) or watermark.run_id != "meta-run-%s-%d" % [owner, int(watermark.launch_sequence)] or not Catalog.fingerprint_valid(watermark.receipt_digest):
			return false
	var seen: Dictionary = {}
	var previous: Dictionary = {}
	for row: Variant in value.entries:
		if not Catalog.exact_fields(row, ENTRY_FIELDS) or not Paths.validate_id(row.profile_id).ok or not Catalog.stable_id(row.run_id) or not Catalog.fingerprint_valid(row.receipt_digest) or row.character_id not in Catalog.CHARACTER_IDS or row.weapon_id not in Catalog.WEAPON_IDS or row.difficulty not in ["normal", "hard", "nightmare"] or row.terminal_reason not in ["death", "victory"]:
			return false
		if not Catalog.bounded_int(row.launch_sequence, 1, Catalog.MAX_VALUE) or row.run_id != "meta-run-%s-%d" % [row.profile_id, int(row.launch_sequence)] or not Catalog.bounded_int(row.completed_floors, 0, 5) or not Catalog.bounded_int(row.completed_rooms, 0, Lifetime.MAX_ROOM_FACTS) or not Catalog.bounded_int(row.run_time_ms, 1, Catalog.MAX_VALUE) or not Catalog.bounded_int(row.score, 0, Catalog.MAX_VALUE) or row.score != score(int(row.completed_floors), int(row.completed_rooms), row.terminal_reason):
			return false
		var identity := canonical({"profile_id": row.profile_id, "run_id": row.run_id, "receipt_digest": row.receipt_digest}).sha256_text()
		if row.id != "record_" + identity or seen.has(row.id) or not value.watermarks.has(row.profile_id) or row.launch_sequence > value.watermarks[row.profile_id].launch_sequence or not previous.is_empty() and ranks_before(row, previous):
			return false
		var watermark: Dictionary = value.watermarks[row.profile_id]
		if row.launch_sequence == watermark.launch_sequence and (row.run_id != watermark.run_id or row.receipt_digest != watermark.receipt_digest):
			return false
		seen[row.id] = true
		previous = row
	return true


static func score(floors: int, rooms: int, reason: String) -> int:
	return floors * 100000 + rooms * 1000 + (1000000 if reason == "victory" else 0)


static func ranks_before(left: Dictionary, right: Dictionary) -> bool:
	if left.score != right.score:
		return left.score > right.score
	if left.run_time_ms != right.run_time_ms:
		return left.run_time_ms < right.run_time_ms
	return left.id < right.id


static func canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(Envelope.canonical_json(value)), "", true, true)


static func same(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(Envelope.canonical_json(left)) == JSON.parse_string(Envelope.canonical_json(right))
