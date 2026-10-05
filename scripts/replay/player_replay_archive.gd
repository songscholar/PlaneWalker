class_name PlayerReplayArchive
extends RefCounted

const Package := preload("res://scripts/replay/player_replay_package.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const Paths := preload("res://scripts/save/save_path_policy.gd")
const MAX_ENTRIES := 20
const MAX_ARCHIVE_BYTES := 64 * 1024 * 1024

var _save: RefCounted
var _save_id := ""
var _binding: Dictionary = {}
var _game_version := ""
var _domain := ""
var _archive: Dictionary = {}
var _busy := false


func configure(root_path: String, game_version: String, binding: Dictionary, profile_id: String, save_domain: String, injector: Callable = Callable()) -> Dictionary:
	if _busy or _save != null or not Paths.validate_id(profile_id).ok or not Paths.validate_id(save_domain).ok:
		return _failure(&"REPLAY_ARCHIVE_CONFIGURATION_INVALID")
	var save := Save.new()
	var result = save.configure(root_path, game_version, binding, Callable(), injector)
	if not result.ok:
		return _failure(result.code)
	_save = save
	_binding = binding.duplicate(true)
	_game_version = game_version
	_domain = save_domain
	_save_id = "replay_" + Envelope.canonical_json({"profile_id": profile_id, "game_version": game_version, "content_snapshot": binding, "save_domain": save_domain}).sha256_text().substr(0, 25)
	var loaded := reload()
	if not loaded.ok:
		_save = null
	return loaded


func snapshot() -> Dictionary:
	return _archive.duplicate(true)


func reload() -> Dictionary:
	if _save == null or _busy:
		return _failure(&"REPLAY_ARCHIVE_NOT_READY")
	_busy = true
	var loaded = _save.load_profile(_save_id, "local")
	if not loaded.ok and loaded.code != &"NOT_FOUND":
		return _finish_failure(loaded.code)
	var value: Variant = loaded.payload.get("player_replay_archive", {}) if loaded.ok else _empty()
	var validated := _validate(value)
	if not validated.ok:
		return _finish_failure(validated.code)
	_archive = validated.context.archive
	_busy = false
	return _success()


func set_fault_injector(injector: Callable) -> void:
	if _save != null:
		_save.set_fault_injector(injector)


func store(replay: Dictionary) -> Dictionary:
	if _save == null or _busy:
		return _failure(&"REPLAY_ARCHIVE_NOT_READY")
	var created := Package.create(replay, _game_version, _binding, _domain)
	return _insert(created.context.package) if created.ok else created


func import_json(encoded: String) -> Dictionary:
	if _save == null or _busy:
		return _failure(&"REPLAY_ARCHIVE_NOT_READY")
	var decoded := Package.decode(encoded, _game_version, _binding, _domain)
	return _insert(decoded.context.package) if decoded.ok else decoded


func load_replay(id: String) -> Dictionary:
	if _save == null or not Package.valid_id(id):
		return _failure(&"REPLAY_ARCHIVE_NOT_FOUND")
	for entry: Dictionary in _archive.get("entries", []):
		if entry.id == id:
			return Package.validate(entry, _game_version, _binding, _domain)
	return _failure(&"REPLAY_ARCHIVE_NOT_FOUND")


func export_json(id: String) -> Dictionary:
	var loaded := load_replay(id)
	if not loaded.ok:
		return loaded
	return _success({"json": JSON.stringify(loaded.context.package, "", true, true)})


func remove(id: String) -> Dictionary:
	if _save == null or _busy or not Package.valid_id(id):
		return _failure(&"REPLAY_ARCHIVE_NOT_READY")
	var candidate := _archive.duplicate(true)
	var found := false
	for index: int in range(candidate.entries.size()):
		if candidate.entries[index].id == id:
			candidate.entries.remove_at(index)
			found = true
			break
	if not found:
		return _failure(&"REPLAY_ARCHIVE_NOT_FOUND")
	candidate.revision += 1
	return _commit(candidate, id)


func _insert(package: Dictionary) -> Dictionary:
	for entry: Dictionary in _archive.entries:
		if entry.id == package.id:
			var primary = _save.inspect_profile(_save_id, "local")
			if not primary.ok or not _same(primary.payload.payload.get("player_replay_archive", {}), _archive):
				return _failure(&"REPLAY_ARCHIVE_STALE_PRIMARY")
			return _success({"id": package.id, "duplicate": true, "reconciled_committed_write": false})
	if _archive.entries.size() >= MAX_ENTRIES or _archive.revision >= 2147483647:
		return _failure(&"REPLAY_ARCHIVE_CAPACITY")
	var candidate := _archive.duplicate(true)
	candidate.entries.append(package.duplicate(true))
	candidate.revision += 1
	return _commit(candidate, package.id)


func _commit(candidate: Dictionary, id: String) -> Dictionary:
	var validation := _validate(candidate)
	if not validation.ok:
		return validation
	_busy = true
	var primary = _save.inspect_profile(_save_id, "local")
	if not primary.ok and primary.code != &"NOT_FOUND":
		return _finish_failure(primary.code)
	var durable: Variant = primary.payload.payload.get("player_replay_archive", {}) if primary.ok else _empty()
	if not _same(durable, _archive):
		return _finish_failure(&"REPLAY_ARCHIVE_STALE_PRIMARY")
	var expected: Dictionary = primary.payload if primary.ok else {}
	var written = _save.save_profile_compare_exchange(_save_id, "local", {"player_replay_archive": candidate}, expected)
	var reconciled := false
	if not written.ok:
		if written.metadata.get("reason", "") == "expected_primary_stale":
			return _finish_failure(&"REPLAY_ARCHIVE_STALE_PRIMARY")
		var inspected = _save.inspect_profile(_save_id, "local")
		if not inspected.ok or not _same(inspected.payload.payload.get("player_replay_archive", {}), candidate):
			_busy = false
			return {"ok": false, "code": written.code, "context": written.metadata.duplicate(true)}
		reconciled = true
	_archive = validation.context.archive
	_busy = false
	return _success({"id": id, "duplicate": false, "reconciled_committed_write": reconciled})


func _validate(value: Variant) -> Dictionary:
	if not value is Dictionary or value.size() != 3 or typeof(value.get("schema_version")) not in [TYPE_INT, TYPE_FLOAT] or value.schema_version != 1 or typeof(value.get("revision")) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value.revision)) or float(value.revision) != floorf(float(value.revision)) or value.revision < 0 or value.revision > 2147483647 or not value.get("entries") is Array or value.entries.size() > MAX_ENTRIES:
		return _failure(&"REPLAY_ARCHIVE_INVALID")
	var candidate := {"schema_version": 1, "revision": int(value.revision), "entries": []}
	var seen: Dictionary = {}
	var bytes := 0
	for entry: Variant in value.entries:
		var validated := Package.validate(entry, _game_version, _binding, _domain)
		if not validated.ok:
			return validated
		var package: Dictionary = validated.context.package
		if seen.has(package.id):
			return _failure(&"REPLAY_ARCHIVE_INVALID")
		seen[package.id] = true
		bytes += JSON.stringify(package).to_utf8_buffer().size()
		if bytes > MAX_ARCHIVE_BYTES:
			return _failure(&"REPLAY_ARCHIVE_CAPACITY")
		candidate.entries.append(package)
	return _success({"archive": candidate})


static func _empty() -> Dictionary:
	return {"schema_version": 1, "revision": 0, "entries": []}


static func _same(left: Variant, right: Variant) -> bool:
	return Envelope._is_json_compatible(left) and Envelope._is_json_compatible(right) and Envelope._json_round_trip(left) == Envelope._json_round_trip(right)


func _finish_failure(code: StringName) -> Dictionary:
	_busy = false
	return _failure(code)


static func _success(context: Dictionary = {}) -> Dictionary:
	return {"ok": true, "code": &"OK", "context": context.duplicate(true)}


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
