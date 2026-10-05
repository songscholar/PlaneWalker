class_name OfflinePlatformProvider
extends "res://scripts/platform/platform_provider.gd"

const Rules := preload("res://scripts/platform/platform_rules.gd")
const Store := preload("res://scripts/platform/platform_state_store.gd")
const Artifacts := preload("res://scripts/platform/platform_local_artifacts.gd")
const Records := preload("res://scripts/community/local_run_records.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
var _store: RefCounted
var _artifacts: RefCounted
var _binding: Dictionary = {}
var _domain := ""
var _record_source: RefCounted
var _busy := false
var _profile_id := ""
var _version := ""


func configure(root: String, version: String, binding: Dictionary, profile_id: String, domain: String) -> Dictionary:
	if _store != null or _busy or not Rules.storage_path_safe(root) or version.length() > 64:
		return failure(&"INVALID_ARGUMENT")
	var store := Store.new()
	var configured := store.configure(root.path_join("state"), version, binding, profile_id, domain)
	if not configured.ok:
		return configured
	var artifacts := Artifacts.new()
	configured = artifacts.configure(root, version, binding, domain)
	if not configured.ok:
		return configured
	_store = store
	_artifacts = artifacts
	_binding = binding.duplicate(true)
	_domain = domain
	_profile_id = profile_id
	_version = version
	return success({"capabilities": CAPABILITIES.duplicate(), "local_authority": true})


func storage_identity() -> Dictionary:
	return {"profile_id": _profile_id, "save_domain": _domain, "content_snapshot": _binding.duplicate(true), "game_version": _version} if _store != null else {}


func configure_local_content(sources: Array, entries: Array, owned_tags: Array) -> Dictionary:
	if _artifacts == null:
		return failure(&"NOT_CONFIGURED")
	return _artifacts.configure_local_content(sources, entries, owned_tags)


func attach_local_records(records: RefCounted) -> Dictionary:
	if not records is Records:
		return failure(&"INVALID_ARGUMENT")
	var board: Dictionary = records.snapshot()
	if board.get("save_domain") != _domain or not Rules.same(board.get("content_snapshot"), _binding):
		return failure(&"RECORD_SCOPE_MISMATCH")
	_record_source = records
	return success()


func set_fault_injector(injector: Callable) -> void:
	if _store != null:
		_store.set_fault_injector(injector)


func perform(operation: String, request: Dictionary = {}) -> Dictionary:
	if operation not in OPERATIONS:
		return failure(&"UNSUPPORTED_OPERATION")
	if not Rules.valid_request(operation, request):
		return failure(&"INVALID_ARGUMENT")
	if _store == null or _busy:
		return failure(&"BUSY" if _busy else &"NOT_CONFIGURED")
	_busy = true
	var refreshed: Dictionary = _store.refresh()
	var result := _perform_ready(operation, request) if refreshed.ok else refreshed
	_busy = false
	return result


func _perform_ready(operation: String, request: Dictionary) -> Dictionary:
	var state: Dictionary = _store.snapshot()
	match operation:
		"status":
			return success({"capabilities": CAPABILITIES.duplicate(), "mode": "OFFLINE", "last_failure": "", "local_authority": true})
		"identity":
			return success(state.identity)
		"set_display_name":
			state.identity.display_name = request.display_name
			return _commit(state, {"display_name": request.display_name})
		"achievements":
			return success({"ids": state.achievements})
		"unlock_achievement":
			if state.achievements.has(request.id):
				return success({"id": request.id, "inserted": false, "duplicate": true, "reconciled_committed_write": false})
			state.achievements.append(request.id)
			state.achievements.sort()
			return _commit(state, {"id": request.id, "inserted": true})
		"cloud_write":
			var previous: Dictionary = state.cloud.get(request.key, {})
			if not request.expected_digest.is_empty() and previous.get("digest", "") != request.expected_digest:
				return failure(&"CLOUD_CONFLICT")
			var digest := Rules.json_digest(request.value)
			state.cloud[request.key] = {"value": request.value.duplicate(true), "digest": digest}
			return _commit(state, {"key": request.key, "digest": digest, "authority": "local"})
		"cloud_read":
			if not state.cloud.has(request.key):
				return failure(&"NOT_FOUND")
			return success({"key": request.key, "value": state.cloud[request.key].value, "digest": state.cloud[request.key].digest, "authority": "local"})
		"share_cloud":
			if not state.cloud.has(request.key):
				return failure(&"NOT_FOUND")
			return _artifacts.share_cloud(request.key, state.cloud[request.key])
		"cloud_list":
			var keys: Array = state.cloud.keys()
			keys.sort()
			var entries: Array[Dictionary] = []
			for key: String in keys:
				entries.append({"key": key, "digest": state.cloud[key].digest})
			return success({"entries": entries, "authority": "local"})
		"cloud_remove":
			if not state.cloud.has(request.key):
				return success({"removed": false, "duplicate": true})
			if not request.expected_digest.is_empty() and state.cloud[request.key].digest != request.expected_digest:
				return failure(&"CLOUD_CONFLICT")
			state.cloud.erase(request.key)
			return _commit(state, {"removed": true})
		"submit_score":
			var entries: Array = state.boards.get(request.board_id, [])
			for entry: Dictionary in entries:
				if entry.id == request.entry_id:
					return success({"duplicate": true, "ranked": false}) if entry.score == request.score and entry.elapsed_ms == request.elapsed_ms else failure(&"ENTRY_CONFLICT")
			if entries.size() >= Rules.MAX_BOARD_ENTRIES:
				return failure(&"PLATFORM_CAPACITY")
			entries.append({"id": request.entry_id, "score": request.score, "elapsed_ms": request.elapsed_ms, "display_name": state.identity.display_name})
			entries.sort_custom(Rules.ranks_before)
			state.boards[request.board_id] = entries
			return _commit(state, {"ranked": false})
		"leaderboard":
			return _leaderboard(state, request)
		"friends":
			return success({"entries": []})
		"presence":
			return success({"activity": state.presence})
		"set_presence":
			state.presence = request.activity
			return _commit(state, {"activity": request.activity})
		"discover_content":
			return _artifacts.discover_content()
		"entitlements":
			return _artifacts.entitlements()
		"share_build":
			return _artifacts.share_build(request.build)
		"share_replay":
			return _artifacts.share_replay(request.package)
		"capture_screenshot":
			return _artifacts.capture_screenshot(request.image)
	return failure(&"UNSUPPORTED_OPERATION")


func _leaderboard(state: Dictionary, request: Dictionary) -> Dictionary:
	var entries: Array = state.boards.get(request.board_id, []).duplicate(true)
	if request.board_id == "runs" and _record_source != null:
		var row: Dictionary = _record_source.provider_row()
		if not row.available:
			return failure(&"LOCAL_RECORDS_PENDING")
		entries.clear()
		for record: Dictionary in _record_source.snapshot().entries:
			entries.append({"id": str(record.id).sha256_text().left(32), "score": int(record.score), "elapsed_ms": int(record.run_time_ms), "display_name": (str(record.character_id) + " / " + str(record.weapon_id)).left(64)})
	if entries.size() > request.limit:
		entries.resize(request.limit)
	return success({"board_id": request.board_id, "scope": "local", "ranked": false, "entries": entries}, "OFFLINE_FALLBACK" if request.scope != "local" else "OFFLINE")


func _commit(state: Dictionary, context: Dictionary) -> Dictionary:
	var committed: Dictionary = _store.commit(state)
	if not committed.ok:
		return committed
	for key: String in context:
		committed.context[key] = context[key]
	return committed
