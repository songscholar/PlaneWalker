extends RefCounted

const Save := preload("res://scripts/save/save_service.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const Paths := preload("res://scripts/save/save_path_policy.gd")
const Rules := preload("res://scripts/platform/platform_rules.gd")
const Provider := preload("res://scripts/platform/platform_provider.gd")
var _save: RefCounted
var _storage_id := ""
var _identity_id := ""
var _state: Dictionary = {}
var _expected: Dictionary = {}
var _busy := false
var _root := ""


func configure(root: String, version: String, binding: Dictionary, profile_id: String, domain: String) -> Dictionary:
	if _save != null or not Rules.storage_path_safe(root) or not Paths.validate_id(profile_id).ok or not Paths.validate_id(domain).ok:
		return Provider.failure(&"INVALID_ARGUMENT")
	var save := Save.new()
	var result = save.configure(root, version, binding)
	if not result.ok:
		return Provider.failure(result.code)
	_identity_id = "local_" + Envelope.sha256_digest({"profile_id": profile_id, "save_domain": domain}).left(26)
	_storage_id = "platform_" + Envelope.sha256_digest({"profile_id": profile_id, "save_domain": domain, "content_snapshot": binding}).left(23)
	_save = save
	_root = ProjectSettings.globalize_path(root).simplify_path()
	if not _safe_scope():
		_save = null
		return Provider.failure(&"UNSAFE_PATH")
	var loaded = _save.load_profile(_storage_id, "local")
	if not loaded.ok and loaded.code != &"NOT_FOUND":
		_save = null
		return Provider.failure(loaded.code)
	var result_state: Variant = loaded.payload.get("platform_state", {}) if loaded.ok else _empty()
	if not Rules.valid_state(result_state, _identity_id):
		_save = null
		return Provider.failure(&"PLATFORM_STATE_INVALID")
	_state = result_state.duplicate(true)
	return refresh()


func refresh() -> Dictionary:
	if _save == null or _busy:
		return Provider.failure(&"BUSY" if _busy else &"NOT_CONFIGURED")
	if not _safe_scope():
		return Provider.failure(&"UNSAFE_PATH")
	var inspected = _save.inspect_profile(_storage_id, "local")
	if not inspected.ok and inspected.code != &"NOT_FOUND":
		return Provider.failure(inspected.code)
	var current: Variant = inspected.payload.payload.get("platform_state", {}) if inspected.ok else _empty()
	if not Rules.valid_state(current, _identity_id):
		return Provider.failure(&"PLATFORM_STATE_INVALID")
	_state = current.duplicate(true)
	_expected = inspected.payload.duplicate(true) if inspected.ok else {}
	return Provider.success()


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func set_fault_injector(injector: Callable) -> void:
	if _save != null:
		_save.set_fault_injector(injector)


func commit(candidate: Dictionary) -> Dictionary:
	if _save == null or _busy:
		return Provider.failure(&"BUSY" if _busy else &"NOT_CONFIGURED")
	if not _safe_scope():
		return Provider.failure(&"UNSAFE_PATH")
	if not Rules.valid_state(candidate, _identity_id):
		return Provider.failure(&"PLATFORM_CAPACITY")
	candidate = JSON.parse_string(Envelope.canonical_json(candidate))
	if Rules.same(candidate, _state):
		return Provider.success({"duplicate": true, "reconciled_committed_write": false})
	_busy = true
	var written = _save.save_profile_compare_exchange(_storage_id, "local", {"platform_state": candidate}, _expected)
	var reconciled := false
	if not written.ok:
		var inspected = _save.inspect_profile(_storage_id, "local")
		if not inspected.ok or not Rules.same(inspected.payload.payload.get("platform_state", {}), candidate):
			_busy = false
			return Provider.failure(&"STALE_PRIMARY" if written.metadata.get("reason") == "expected_primary_stale" else written.code)
		reconciled = true
	_state = candidate.duplicate(true)
	_busy = false
	return Provider.success({"duplicate": false, "reconciled_committed_write": reconciled})


func _empty() -> Dictionary:
	return {"schema_version": 1, "identity": {"id": _identity_id, "display_name": "Plane Walker"}, "achievements": [], "cloud": {}, "boards": {}, "presence": "offline"}


func _safe_scope() -> bool:
	var scope := _root.path_join("profiles").path_join(_storage_id).path_join("local")
	if not Rules.storage_path_safe(scope):
		return false
	for filename: String in ["primary.json", "pending.tmp", "backup_1.json", "backup_2.json"]:
		if not Rules.storage_path_safe(scope.path_join(filename)):
			return false
	return true
