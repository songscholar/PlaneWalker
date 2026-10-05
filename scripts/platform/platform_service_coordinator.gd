class_name PlatformServiceCoordinator
extends RefCounted

const Provider := preload("res://scripts/platform/platform_provider.gd")
const Rules := preload("res://scripts/platform/platform_rules.gd")
const ProfileService := preload("res://scripts/progression/profile_runtime_service.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const Stream := preload("res://scripts/replay/run_replay_stream_store.gd")
const MAX_PROFILE_BYTES := 8 * 1024 * 1024
const BACKUP_FIELDS := ["schema_id", "schema_version", "profile_id", "save_domain", "content_snapshot", "encoding", "data", "compressed_sha256", "payload_sha256"]
var _provider: RefCounted
var _profile: RefCounted
var _revision := 0
var _model: Dictionary = {}
var _busy := false
var _replay_library: Node
var _notice_key := ""
var _artifact_path := ""
var _share_code := ""


func configure(provider: RefCounted, profile: RefCounted) -> Dictionary:
	if _provider != null or not provider is Provider or not profile is ProfileService or profile.snapshot().is_empty() or not provider.status().ok:
		return Provider.failure(&"INVALID_ARGUMENT")
	var scope: Dictionary = provider.storage_identity()
	var identity: Dictionary = profile.local_record_storage_identity()
	for field: String in ["profile_id", "save_domain", "content_snapshot"]:
		if not Rules.same(scope.get(field), identity.get(field)):
			return Provider.failure(&"PROFILE_SCOPE_MISMATCH")
	_provider = provider
	_profile = profile
	return refresh()


func attach_replay_library(library: Node) -> Dictionary:
	if not is_instance_valid(library) or not library.has_method("rows") or not library.has_method("export_recording"):
		return Provider.failure(&"INVALID_ARGUMENT")
	_replay_library = library
	return Provider.success()


func snapshot() -> Dictionary:
	return {"revision": _revision, "model": _model.duplicate(true)}


func refresh() -> Dictionary:
	if _provider == null or _busy:
		return Provider.failure(&"BUSY" if _busy else &"NOT_CONFIGURED")
	var identity: Dictionary = _provider.identity()
	var achievements: Dictionary = _provider.achievements()
	var cloud: Dictionary = _provider.cloud_list()
	if not identity.ok or not achievements.ok or not cloud.ok:
		return identity if not identity.ok else (achievements if not achievements.ok else cloud)
	var friends: Dictionary = _provider.friends()
	var presence: Dictionary = _provider.presence()
	var board: Dictionary = _provider.leaderboard()
	var content: Dictionary = _provider.discover_content()
	var entitlements: Dictionary = _provider.entitlements()
	var status: Dictionary = _provider.status()
	_model = {"identity": identity.context, "achievements": achievements.context.ids, "cloud": cloud.context.entries, "friends": friends.context.get("entries", []), "presence": presence.context.get("activity", "offline"), "leaderboard": board.context.get("entries", []), "content": content.context.get("entries", []), "entitlements": entitlements.context.get("entries", []), "status": status.context.get("mode", "OFFLINE"), "builds": _profile.snapshot().get("build_library", []), "replays": _replay_library.rows() if is_instance_valid(_replay_library) else [], "notice_key": _notice_key, "artifact_path": _artifact_path, "share_code": _share_code}
	_revision += 1
	return Provider.success(snapshot())


func execute(command: String, request: Dictionary, expected_revision: int) -> Dictionary:
	if _provider == null or _busy:
		return Provider.failure(&"BUSY" if _busy else &"NOT_CONFIGURED")
	if expected_revision != _revision:
		return Provider.failure(&"STALE_REVISION")
	_busy = true
	var result := _execute_ready(command, request)
	_busy = false
	if result.ok:
		_notice_key = "UI_PLATFORM_EXPORTED" if result.context.has("path") else "UI_PLATFORM_SAVED"
		_artifact_path = str(result.context.get("path", ""))
		_share_code = str(result.context.get("share_code", ""))
		refresh()
	return result


func _execute_ready(command: String, request: Dictionary) -> Dictionary:
	match command:
		"rename":
			return _provider.perform("set_display_name", request)
		"backup_profile", "export_profile":
			if not request.is_empty():
				return Provider.failure(&"INVALID_ARGUMENT")
			var backup := _create_profile_backup()
			if not backup.ok:
				return backup
			var written: Dictionary = _provider.cloud_write("profile_backup", backup.context.value)
			if not written.ok:
				return written
			return _provider.share_cloud("profile_backup") if command == "export_profile" else written
		"export_cloud":
			return _provider.perform("share_cloud", request)
		"share_build":
			if not Rules.fields(request, ["build_id"]) or not Rules.id(request.build_id):
				return Provider.failure(&"INVALID_ARGUMENT")
			for build: Dictionary in _profile.snapshot().get("build_library", []):
				if build.id == request.build_id:
					return _provider.share_build(build)
			return Provider.failure(&"NOT_FOUND")
		"share_replay":
			if not Rules.fields(request, ["id"]) or not request.id is String or request.id.length() > 80 or not is_instance_valid(_replay_library):
				return Provider.failure(&"INVALID_ARGUMENT")
			var allowed := false
			for row: Dictionary in _replay_library.rows():
				allowed = allowed or row.id == request.id
			if not allowed:
				return Provider.failure(&"NOT_FOUND")
			var exported: Dictionary = _replay_library.export_recording(request.id)
			if not exported.ok:
				return exported
			var file := FileAccess.open(str(exported.context.path), FileAccess.READ)
			if file == null or file.get_length() > Stream.MAX_PACKAGE_BYTES:
				return Provider.failure(&"INVALID_ARGUMENT")
			var package: Variant = JSON.parse_string(file.get_as_text())
			return _provider.share_replay(package) if package is Dictionary else Provider.failure(&"INVALID_ARGUMENT")
		"screenshot":
			return _provider.perform("capture_screenshot", request)
		"refresh":
			return Provider.success() if request.is_empty() else Provider.failure(&"INVALID_ARGUMENT")
	return Provider.failure(&"UNSUPPORTED_OPERATION")


func _create_profile_backup() -> Dictionary:
	var identity: Dictionary = _profile.local_record_storage_identity()
	var scope: Dictionary = _provider.storage_identity()
	for field: String in ["profile_id", "save_domain", "content_snapshot"]:
		if not Rules.same(scope.get(field), identity.get(field)):
			return Provider.failure(&"PROFILE_SCOPE_MISMATCH")
	var payload := Envelope.canonical_json(_profile.payload())
	var bytes := payload.to_utf8_buffer()
	if bytes.is_empty() or bytes.size() > MAX_PROFILE_BYTES:
		return Provider.failure(&"PLATFORM_CAPACITY")
	var compressed := bytes.compress(FileAccess.COMPRESSION_GZIP)
	var value := {"schema_id": "planewalker.profile_backup", "schema_version": 1, "profile_id": identity.profile_id, "save_domain": identity.save_domain, "content_snapshot": identity.content_snapshot, "encoding": "gzip_base64", "data": Marshalls.raw_to_base64(compressed), "compressed_sha256": _byte_digest(compressed), "payload_sha256": payload.sha256_text()}
	return Provider.success({"value": value}) if Rules.bounded_json(value) else Provider.failure(&"PLATFORM_CAPACITY")


func decode_profile_backup(value: Dictionary) -> Dictionary:
	if _provider == null or not Rules.fields(value, BACKUP_FIELDS) or not Rules.bounded_json(value) or value.schema_id != "planewalker.profile_backup" or value.schema_version != 1 or value.encoding != "gzip_base64" or not value.data is String or not Rules.digest(value.compressed_sha256) or not Rules.digest(value.payload_sha256):
		return Provider.failure(&"INVALID_ARGUMENT")
	var identity: Dictionary = _provider.storage_identity()
	for field: String in ["profile_id", "save_domain", "content_snapshot"]:
		if not Rules.same(identity.get(field), value.get(field)):
			return Provider.failure(&"PROFILE_SCOPE_MISMATCH")
	var compressed := Marshalls.base64_to_raw(value.data)
	if compressed.size() < 18 or Marshalls.raw_to_base64(compressed) != value.data or _byte_digest(compressed) != value.compressed_sha256 or compressed[0] != 31 or compressed[1] != 139 or compressed.decode_u32(compressed.size() - 4) > MAX_PROFILE_BYTES:
		return Provider.failure(&"INVALID_ARGUMENT")
	var bytes := compressed.decompress_dynamic(MAX_PROFILE_BYTES, FileAccess.COMPRESSION_GZIP)
	if bytes.is_empty() or bytes.get_string_from_utf8().sha256_text() != value.payload_sha256:
		return Provider.failure(&"INVALID_ARGUMENT")
	var payload: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	return Provider.success({"payload": payload}) if payload is Dictionary else Provider.failure(&"INVALID_ARGUMENT")


static func _byte_digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()
