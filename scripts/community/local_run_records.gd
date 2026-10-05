class_name LocalRunRecords
extends RefCounted

const ProfileService := preload("res://scripts/progression/profile_runtime_service.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Paths := preload("res://scripts/save/save_path_policy.gd")
const Rules := preload("res://scripts/community/local_run_record_rules.gd")
const MAX_ENTRIES := Rules.MAX_ENTRIES
const MAX_OWNERS := Rules.MAX_OWNERS

var _service: RefCounted
var _save: RefCounted
var _binding: Dictionary = {}
var _domain := ""
var _board_id := ""
var _board: Dictionary = {}
var _busy := false
var _root_path := ""
var _game_version := ""
var _fault_injector: Callable


func configure(service: RefCounted, root_path: String, game_version: String, content_snapshot: Dictionary, save_domain: String, fault_injector: Callable = Callable()) -> Dictionary:
	if _busy or not service is ProfileService or not Paths.validate_id(save_domain).ok:
		return _failure(&"CONFIGURATION_INVALID")
	var source_identity: Dictionary = service.local_record_storage_identity()
	if source_identity.get("save_domain") != save_domain or not _same(source_identity.get("content_snapshot"), content_snapshot):
		return _failure(&"RECORD_SCOPE_MISMATCH")
	var storage := Save.new()
	var configured = storage.configure(root_path, game_version, content_snapshot, Callable(), fault_injector)
	if not configured.ok:
		return _failure(configured.code)
	var id := Rules.board_id(content_snapshot, save_domain)
	var loaded = storage.load_profile(id, "local")
	if not loaded.ok and loaded.code != &"NOT_FOUND":
		return _failure(loaded.code)
	var value: Dictionary = loaded.payload.get("local_run_records", {}) if loaded.ok else _empty_board(content_snapshot, save_domain)
	if not _valid_board(value, content_snapshot, save_domain):
		return _failure(&"BOARD_INVALID")
	_service = service
	_save = storage
	_binding = content_snapshot.duplicate(true)
	_domain = save_domain
	_board_id = id
	_board = _normalized_board(value)
	_root_path = root_path
	_game_version = game_version
	_fault_injector = fault_injector
	return _success({})


func snapshot() -> Dictionary:
	return _board.duplicate(true)


func set_fault_injector(fault_injector: Callable) -> void:
	_fault_injector = fault_injector
	if _save != null:
		_save.set_fault_injector(fault_injector)


func sync_settled_run() -> Dictionary:
	if _busy or _service == null:
		return _failure(&"BUSY" if _busy else &"NOT_CONFIGURED")
	_busy = true
	var verified: Dictionary = _service.verified_local_record_outbox()
	if not verified.ok:
		return _finish_failure(verified.code)
	var refreshed := _read_current_board()
	if not refreshed.ok:
		return _finish_failure(refreshed.code)
	if verified.context.sources.is_empty():
		return _finish_failure(&"NO_SETTLED_RUN")
	var inserted := false
	var reconciled := false
	var acknowledgement_pending := false
	var published_boards: Dictionary = {}
	for source: Dictionary in verified.context.sources:
		if source.save_domain != _domain:
			return _finish_failure(&"RECORD_SCOPE_MISMATCH")
		var storage: RefCounted = _save
		var id := _board_id
		if not _same(source.content_snapshot, _binding):
			storage = Save.new()
			var configured = storage.configure(_root_path, _game_version, source.content_snapshot, Callable(), _fault_injector)
			if not configured.ok:
				return _finish_failure(configured.code)
			id = Rules.board_id(source.content_snapshot, _domain)
		var published := _publish_source(source, storage, id)
		if not published.ok:
			return _finish_failure(published.code)
		inserted = inserted or published.context.inserted
		reconciled = reconciled or published.context.reconciled_committed_write
		published_boards[id] = storage
	for id: String in published_boards:
		var acknowledged: Dictionary = _service.acknowledge_local_records(published_boards[id], id)
		acknowledgement_pending = acknowledgement_pending or not acknowledged.ok
	_busy = false
	return _success({"inserted": inserted, "reconciled_committed_write": reconciled, "acknowledgement_pending": acknowledgement_pending})


func _read_current_board() -> Dictionary:
	var primary = _save.inspect_profile(_board_id, "local")
	if not primary.ok and primary.code != &"NOT_FOUND":
		return _failure(primary.code)
	var durable: Dictionary = primary.payload.payload.get("local_run_records", {}) if primary.ok else _empty_board(_binding, _domain)
	if not _valid_board(durable, _binding, _domain):
		return _failure(&"BOARD_INVALID")
	_board = _normalized_board(durable)
	return _success({})


func _publish_source(source: Dictionary, storage: RefCounted, id: String) -> Dictionary:
	var primary = storage.inspect_profile(id, "local")
	if not primary.ok and primary.code != &"NOT_FOUND":
		return _failure(primary.code)
	var durable: Dictionary = primary.payload.payload.get("local_run_records", {}) if primary.ok else _empty_board(source.content_snapshot, _domain)
	if not _valid_board(durable, source.content_snapshot, _domain):
		return _failure(&"BOARD_INVALID")
	durable = _normalized_board(durable)
	var record := _record(source)
	if record.is_empty():
		return _failure(&"RECORD_INVALID")
	var watermark: Dictionary = durable.watermarks.get(source.profile_id, {})
	if not watermark.is_empty() and record.launch_sequence <= watermark.launch_sequence:
		if record.launch_sequence == watermark.launch_sequence and (record.run_id != watermark.run_id or record.receipt_digest != watermark.receipt_digest):
			return _failure(&"RECORD_IDENTITY_CONFLICT")
		return _success({"inserted": false, "reconciled_committed_write": false})
	if watermark.is_empty() and durable.watermarks.size() >= MAX_OWNERS:
		return _failure(&"OWNER_LIMIT")
	var candidate := durable.duplicate(true)
	candidate.entries.append(record)
	candidate.entries.sort_custom(_ranks_before)
	if candidate.entries.size() > MAX_ENTRIES:
		candidate.entries.resize(MAX_ENTRIES)
	candidate.watermarks[source.profile_id] = {"launch_sequence": record.launch_sequence, "run_id": record.run_id, "receipt_digest": record.receipt_digest}
	var expected: Dictionary = primary.payload if primary.ok else {}
	var written = storage.save_profile_compare_exchange(id, "local", {"local_run_records": candidate}, expected)
	var reconciled := false
	if not written.ok:
		var inspected = storage.inspect_profile(id, "local")
		if not inspected.ok or not _same(inspected.payload.payload.get("local_run_records", {}), candidate):
			return _failure(&"STALE_PRIMARY" if written.metadata.get("reason") == "expected_primary_stale" else written.code)
		reconciled = true
	if id == _board_id:
		_board = candidate.duplicate(true)
	return _success({"inserted": true, "reconciled_committed_write": reconciled})


func provider_row() -> Dictionary:
	var row := {"id": "leaderboard", "status": "AVAILABLE", "entries": [], "available": true, "reason_key": "", "cost": {"chronos_shards": 0, "existential_imprints": 0}}
	if _service == null or _busy:
		row.status = "UNAVAILABLE"
		row.available = false
		row.reason_key = "HUB_PROVIDER_UNAVAILABLE"
		return row
	var synchronized := sync_settled_run()
	if not synchronized.ok and synchronized.code not in [&"NO_SETTLED_RUN"]:
		row.status = "UNAVAILABLE"
		row.available = false
		row.reason_key = "UI_COMMUNITY_SAVE_PENDING"
		return row
	for index: int in range(mini(20, _board.entries.size())):
		var record: Dictionary = _board.entries[index]
		var caption := "%d. %s / %s / %.1fs" % [index + 1, tr("CHARACTER_%s_NAME" % record.character_id.to_upper()), tr("WEAPON_%s_NAME" % record.weapon_id.to_upper()), float(record.run_time_ms) / 1000.0]
		if _domain != "base":
			caption = tr("UI_COMMUNITY_UNRANKED") + " / " + caption
		row.entries.append({"id": record.id, "name": caption.left(96), "score": int(record.score)})
	return row


static func _record(source: Dictionary) -> Dictionary:
	return Rules.record(source)


static func _empty_board(binding: Dictionary, domain: String) -> Dictionary:
	return {"schema_version": 1, "content_snapshot": binding.duplicate(true), "save_domain": domain, "entries": [], "watermarks": {}}


static func _normalized_board(value: Dictionary) -> Dictionary:
	var normalized := value.duplicate(true)
	normalized.schema_version = int(normalized.schema_version)
	for record: Dictionary in normalized.entries:
		for field: String in ["launch_sequence", "completed_floors", "completed_rooms", "run_time_ms", "score"]:
			record[field] = int(record[field])
	for watermark: Dictionary in normalized.watermarks.values():
		watermark.launch_sequence = int(watermark.launch_sequence)
	return normalized


static func _valid_board(value: Dictionary, binding: Dictionary, domain: String) -> bool:
	return Rules.valid_board(value, binding, domain)


static func _ranks_before(left: Dictionary, right: Dictionary) -> bool:
	return Rules.ranks_before(left, right)


static func _same(left: Variant, right: Variant) -> bool:
	return Rules.same(left, right)


func _finish_failure(code: StringName) -> Dictionary:
	_busy = false
	return _failure(code)


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}


static func _success(context: Dictionary) -> Dictionary:
	return {"ok": true, "code": &"OK", "context": context.duplicate(true)}
