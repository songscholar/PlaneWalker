extends RefCounted

const Codec := preload("res://scripts/replay/run_replay_chunk_codec.gd")
const Recorder := preload("res://scripts/replay/replay_recorder.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const Paths := preload("res://scripts/save/save_path_policy.gd")
const MAX_ENTRIES := 20
const MAX_OBSERVATIONS := 164048
const MAX_CHUNKS := 2048
const MAX_RUN_BYTES := 64 * 1024 * 1024
const MAX_ARCHIVE_BYTES := 256 * 1024 * 1024
const MAX_PHYSICAL_BYTES := MAX_ARCHIVE_BYTES
const MAX_IDENTITY_BYTES := 1024 * 1024
const MAX_PACKAGE_BYTES := 96 * 1024 * 1024
const DESCRIPTOR_FIELDS := ["schema_id", "schema_version", "first_sequence", "last_sequence", "observation_count", "raw_size", "compressed_size", "raw_sha256", "compressed_sha256"]
const ENTRY_FIELDS := ["id", "identity_base64", "identity_sha256", "seed", "status", "observation_count", "compressed_bytes", "chunks"]
const STATUSES := ["RECORDING", "COMPLETE", "INTERRUPTED", "FAILED"]

var _save: RefCounted
var _save_id := ""
var _directory := ""
var _manifest: Dictionary = {}
var _busy := false
var _compatibility: Dictionary = {}
var _cached_digest := ""
var _cached_observations: Array = []
var _manifest_directory := ""


func configure(root_path: String, game_version: String, binding: Dictionary, profile_id: String, save_domain: String, injector: Callable = Callable()) -> Dictionary:
	if _save != null or _busy or not Paths.validate_id(profile_id).ok or not Paths.validate_id(save_domain).ok:
		return _failure(&"RUN_REPLAY_STORE_CONFIGURATION_INVALID")
	var save := Save.new()
	var result = save.configure(root_path, game_version, binding, Callable(), injector)
	if not result.ok:
		return _failure(result.code)
	_save_id = "stream_" + Envelope.canonical_json({"game_version": game_version, "content_snapshot": binding, "profile_id": profile_id, "save_domain": save_domain}).sha256_text().substr(0, 25)
	_directory = ProjectSettings.globalize_path(root_path).path_join("chunks").path_join(_save_id)
	_manifest_directory = ProjectSettings.globalize_path(root_path).path_join("profiles").path_join(_save_id).path_join("local")
	if DirAccess.make_dir_recursive_absolute(_directory) != OK:
		return _failure(&"RUN_REPLAY_STORE_IO_FAILED")
	_save = save
	_compatibility = {"game_version": game_version, "content_snapshot": binding.duplicate(true)}
	var loaded := reload()
	if not loaded.ok:
		_save = null
	return loaded


func storage_identity() -> Dictionary:
	return {"manifest_id": _save_id, "chunk_directory": _directory}


func snapshot() -> Dictionary:
	return _manifest.duplicate(true)


func rows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _manifest.get("entries", []):
		var identity: Dictionary = _decode_identity(entry).context.identity
		result.append({"id": entry.id, "character_id": identity.character_id, "weapon_id": identity.weapon_id, "seed": entry.seed, "status": entry.status, "observation_count": entry.observation_count, "compressed_bytes": entry.compressed_bytes})
	return result


func identity(id: String) -> Dictionary:
	var entry := _entry(id)
	return _decode_identity(entry) if not entry.is_empty() else _failure(&"RUN_REPLAY_STORE_NOT_FOUND")


func reload() -> Dictionary:
	if _save == null or _busy:
		return _failure(&"RUN_REPLAY_STORE_NOT_READY")
	_busy = true
	var loaded = _save.load_profile(_save_id, "local")
	if not loaded.ok and loaded.code != &"NOT_FOUND":
		return _finish_failure(loaded.code)
	var value: Variant = loaded.payload.get("run_replay_streams", {}) if loaded.ok else _empty()
	var validated := _validate(value)
	if not validated.ok:
		return _finish_failure(validated.code)
	_manifest = validated.context.manifest
	_cached_digest = ""
	_cached_observations.clear()
	_busy = false
	return _success()


func set_fault_injector(injector: Callable) -> void:
	if _save != null:
		_save.set_fault_injector(injector)


func begin(player_identity: Dictionary, seed: int) -> Dictionary:
	if _save == null or _busy:
		return _failure(&"RUN_REPLAY_STORE_NOT_READY")
	if Recorder.validate_full_player_identity(player_identity).is_empty() or not Codec._safe(player_identity) or not _integer(seed, -2147483648, 2147483647):
		return _failure(&"RUN_REPLAY_STORE_IDENTITY_INVALID")
	var bytes := var_to_bytes(player_identity)
	if bytes.size() > MAX_IDENTITY_BYTES or _manifest.entries.size() >= MAX_ENTRIES:
		return _failure(&"RUN_REPLAY_STORE_CAPACITY")
	var id := Codec.byte_digest(Crypto.new().generate_random_bytes(32))
	var candidate := _manifest.duplicate(true)
	candidate.entries.append({"id": id, "identity_base64": Marshalls.raw_to_base64(bytes), "identity_sha256": Codec.byte_digest(bytes), "seed": seed, "status": "RECORDING", "observation_count": 0, "compressed_bytes": 0, "chunks": []})
	candidate.revision += 1
	return _commit(candidate, id)


func append(id: String, observations: Array) -> Dictionary:
	if _save == null or _busy:
		return _failure(&"RUN_REPLAY_STORE_NOT_READY")
	var entry := _entry(id)
	if entry.is_empty() or entry.status != "RECORDING" or observations.is_empty() or observations.size() > Codec.MAX_OBSERVATIONS or not observations[0] is Dictionary or observations[0].get("sequence") != entry.observation_count:
		return _failure(&"RUN_REPLAY_STORE_SEQUENCE_INVALID")
	var admitted: Array[Dictionary] = []
	for value: Variant in observations:
		if not value is Dictionary:
			return _failure(&"RUN_REPLAY_STORE_SEQUENCE_INVALID")
		admitted.append(value)
	var encoded := Codec.encode(admitted)
	if not encoded.ok:
		return encoded
	var chunk: Dictionary = encoded.context.chunk
	var candidate := _manifest.duplicate(true)
	var target: Dictionary = candidate.entries[_index(id)]
	var descriptor := chunk.duplicate(true)
	descriptor.erase("bytes")
	target.chunks.append(descriptor)
	target.observation_count += chunk.observation_count
	target.compressed_bytes += chunk.compressed_size
	candidate.revision += 1
	var validation := _validate(candidate)
	if not validation.ok:
		return validation
	# Publish immutable authenticated bytes before promoting their manifest reference.
	var written := _write_chunk(chunk)
	return _commit(candidate, id, false) if written.ok else written


func read(id: String, sequence: int) -> Dictionary:
	var entry := _entry(id)
	if _save == null or entry.is_empty() or sequence < 0 or sequence >= int(entry.observation_count):
		return _failure(&"RUN_REPLAY_STORE_NOT_FOUND")
	for descriptor: Dictionary in entry.chunks:
		if sequence >= int(descriptor.first_sequence) and sequence <= int(descriptor.last_sequence):
			var decoded := _observations(descriptor)
			if not decoded.ok:
				return decoded
			return _success({"observation": decoded.context.observations[sequence - int(descriptor.first_sequence)]})
	return _failure(&"RUN_REPLAY_STORE_NOT_FOUND")


func _observations(descriptor: Dictionary) -> Dictionary:
	# Authenticate disk even for a cached chunk so removal/corruption never hides.
	var loaded := _read_chunk(descriptor)
	if not loaded.ok:
		return loaded
	if _cached_digest == descriptor.compressed_sha256:
		return _success({"observations": _cached_observations})
	var decoded := Codec.decode(loaded.context.chunk)
	if decoded.ok:
		_cached_digest = descriptor.compressed_sha256
		_cached_observations = decoded.context.observations.duplicate(true)
	return decoded


func transition_rows(id: String) -> Dictionary:
	var entry := _entry(id)
	if entry.is_empty():
		return _failure(&"RUN_REPLAY_STORE_NOT_FOUND")
	var rows: Array[Dictionary] = []
	for descriptor: Dictionary in entry.chunks:
		var decoded := _observations(descriptor)
		if not decoded.ok:
			return decoded
		for observation: Dictionary in decoded.context.observations:
			if observation.get("kind") != "frame":
				rows.append({"sequence": observation.sequence, "kind": str(observation.get("kind", "")), "floor_id": str(observation.get("scene", {}).get("binding", {}).get("floor_id", "")), "room_id": str(observation.get("scene", {}).get("binding", {}).get("node_id", ""))})
	return _success({"rows": rows})


func export_json(id: String) -> Dictionary:
	var entry := _entry(id)
	if entry.is_empty() or entry.status == "RECORDING":
		return _failure(&"RUN_REPLAY_STORE_STATUS_INVALID")
	var chunks: Array[Dictionary] = []
	for descriptor: Dictionary in entry.chunks:
		var loaded := _read_chunk(descriptor)
		if not loaded.ok:
			return loaded
		if not Codec.decode(loaded.context.chunk).ok:
			return _failure(&"RUN_REPLAY_CHUNK_INVALID")
		chunks.append({"digest": descriptor.compressed_sha256, "base64": Marshalls.raw_to_base64(loaded.context.chunk.bytes)})
	var package := {"schema_id": "planewalker.run_replay_package", "schema_version": 1, "compatibility": _compatibility.duplicate(true), "entry": entry, "chunks": chunks}
	var encoded := JSON.stringify(package)
	return _success({"json": encoded}) if encoded.to_utf8_buffer().size() <= MAX_PACKAGE_BYTES else _failure(&"RUN_REPLAY_STORE_CAPACITY")


func import_json(encoded: String) -> Dictionary:
	if _save == null or _busy or encoded.is_empty() or encoded.to_utf8_buffer().size() > MAX_PACKAGE_BYTES:
		return _failure(&"RUN_REPLAY_PACKAGE_INVALID")
	var checked := validate_package(JSON.parse_string(encoded), str(_compatibility.game_version), _compatibility.content_snapshot)
	if not checked.ok:
		return checked
	var entry: Dictionary = checked.context.package.entry
	var existing := _entry(entry.id)
	if not existing.is_empty():
		return _success({"id": entry.id}) if _same(existing, entry) else _failure(&"RUN_REPLAY_PACKAGE_INVALID")
	var candidate := _manifest.duplicate(true)
	candidate.entries.append(entry)
	candidate.revision += 1
	var admitted := _validate(candidate)
	if not admitted.ok:
		return admitted
	for chunk: Dictionary in checked.context.decoded_chunks:
		var written := _write_chunk(chunk)
		if not written.ok:
			return written
	return _commit(candidate, str(entry.id))


static func validate_package(parsed: Variant, game_version: String, binding: Dictionary) -> Dictionary:
	if not parsed is Dictionary or not _fields(parsed, ["schema_id", "schema_version", "compatibility", "entry", "chunks"]) or parsed.schema_id != "planewalker.run_replay_package" or parsed.schema_version != 1 or not parsed.compatibility is Dictionary or not parsed.entry is Dictionary or not parsed.chunks is Array:
		return _failure(&"RUN_REPLAY_PACKAGE_INVALID")
	if not _same(parsed.compatibility, {"game_version": game_version, "content_snapshot": binding}):
		return _failure(&"REPLAY_PACKAGE_INCOMPATIBLE")
	if JSON.stringify(parsed).to_utf8_buffer().size() > MAX_PACKAGE_BYTES:
		return _failure(&"RUN_REPLAY_STORE_CAPACITY")
	var validated := _validate({"schema_version": 1, "revision": 0, "entries": [parsed.entry]})
	if not validated.ok or parsed.entry.get("status") == "RECORDING" or parsed.chunks.size() != parsed.entry.get("chunks", []).size():
		return _failure(&"RUN_REPLAY_PACKAGE_INVALID")
	var entry: Dictionary = validated.context.manifest.entries[0]
	var chunks: Array[Dictionary] = []
	for index: int in range(parsed.chunks.size()):
		var source: Variant = parsed.chunks[index]
		var descriptor: Dictionary = entry.chunks[index]
		if not source is Dictionary or not _fields(source, ["digest", "base64"]) or source.digest != descriptor.compressed_sha256 or not source.base64 is String or source.base64.length() > MAX_PACKAGE_BYTES or source.base64.length() % 4 != 0:
			return _failure(&"RUN_REPLAY_PACKAGE_INVALID")
		var chunk := descriptor.duplicate(true)
		chunk.bytes = Marshalls.base64_to_raw(source.base64)
		if Marshalls.raw_to_base64(chunk.bytes) != source.base64 or not Codec.decode(chunk).ok:
			return _failure(&"RUN_REPLAY_PACKAGE_INVALID")
		chunks.append(chunk)
	var package: Dictionary = parsed.duplicate(true)
	package.entry = entry
	return _success({"package": package, "decoded_chunks": chunks})


func finish(id: String, status: String) -> Dictionary:
	if _save == null or _busy:
		return _failure(&"RUN_REPLAY_STORE_NOT_READY")
	var entry := _entry(id)
	if entry.is_empty() or entry.status != "RECORDING" or status not in ["COMPLETE", "INTERRUPTED", "FAILED"] or status == "COMPLETE" and entry.observation_count == 0:
		return _failure(&"RUN_REPLAY_STORE_STATUS_INVALID")
	if status == "COMPLETE":
		for descriptor: Dictionary in entry.chunks:
			var loaded := _read_chunk(descriptor)
			if not loaded.ok:
				return loaded
			var decoded := Codec.decode(loaded.context.chunk)
			if not decoded.ok:
				return decoded
	var candidate := _manifest.duplicate(true)
	candidate.entries[_index(id)].status = status
	candidate.revision += 1
	return _commit(candidate, id)


func remove(id: String) -> Dictionary:
	if _save == null or _busy or _index(id) < 0:
		return _failure(&"RUN_REPLAY_STORE_NOT_FOUND")
	var candidate := _manifest.duplicate(true)
	candidate.entries.remove_at(_index(id))
	candidate.revision += 1
	return _commit(candidate, id)


func collect_garbage() -> Dictionary:
	if _save == null or _busy:
		return _failure(&"RUN_REPLAY_STORE_NOT_READY")
	var referenced: Dictionary = {}
	# Both recovery generations must retain every referenced immutable chunk.
	for filename: String in [Save.PRIMARY_FILE, Save.PENDING_FILE, Save.BACKUP_ONE_FILE, Save.BACKUP_TWO_FILE]:
		var path := _manifest_directory.path_join(filename)
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > 16 * 1024 * 1024:
			return _failure(&"RUN_REPLAY_STORE_IO_FAILED")
		var checked = Envelope.validate(JSON.parse_string(file.get_as_text()), &"profile", _save_id, "local")
		file.close()
		if not checked.ok or not _same(checked.payload.content_snapshot, _compatibility.content_snapshot):
			return _failure(&"RUN_REPLAY_STORE_MANIFEST_INVALID")
		var validated := _validate(checked.payload.payload.get("run_replay_streams", {}))
		if not validated.ok:
			return validated
		for entry: Dictionary in validated.context.manifest.entries:
			for chunk: Dictionary in entry.chunks:
				referenced[str(chunk.compressed_sha256) + ".zst"] = true
	var directory := DirAccess.open(_directory)
	if directory == null:
		return _failure(&"RUN_REPLAY_STORE_IO_FAILED")
	var reclaimed := 0
	for filename: String in directory.get_files():
		if filename.ends_with(".zst") and Recorder._is_sha256(filename.trim_suffix(".zst")) and not referenced.has(filename):
			if directory.remove(filename) != OK:
				return _failure(&"RUN_REPLAY_STORE_IO_FAILED")
			reclaimed += 1
	return _success({"reclaimed_chunks": reclaimed})


func _commit(candidate: Dictionary, id: String, reclaim: bool = true) -> Dictionary:
	var validated := _validate(candidate)
	if not validated.ok:
		return validated
	_busy = true
	var primary = _save.inspect_profile(_save_id, "local")
	if not primary.ok and primary.code != &"NOT_FOUND":
		return _finish_failure(primary.code)
	var durable: Variant = primary.payload.payload.get("run_replay_streams", {}) if primary.ok else _empty()
	if not _same(durable, _manifest):
		return _finish_failure(&"RUN_REPLAY_STORE_STALE_PRIMARY")
	var written = _save.save_profile_compare_exchange(_save_id, "local", {"run_replay_streams": candidate}, primary.payload if primary.ok else {})
	var reconciled := false
	if not written.ok:
		var inspected = _save.inspect_profile(_save_id, "local")
		if not inspected.ok or not _same(inspected.payload.payload.get("run_replay_streams", {}), candidate):
			return _finish_failure(written.code)
		reconciled = true
	_manifest = validated.context.manifest
	_busy = false
	# Recovery-manifest scanning belongs to archive boundaries, not every batch.
	if reclaim:
		collect_garbage()
	return _success({"id": id, "reconciled_committed_write": reconciled})


func _write_chunk(chunk: Dictionary) -> Dictionary:
	var path := _directory.path_join(str(chunk.compressed_sha256) + ".zst")
	if FileAccess.file_exists(path):
		return _read_chunk(chunk)
	var directory := DirAccess.open(_directory)
	if directory == null:
		return _failure(&"RUN_REPLAY_STORE_IO_FAILED")
	var retained_bytes := 0
	for filename: String in directory.get_files():
		var retained := FileAccess.open(_directory.path_join(filename), FileAccess.READ)
		if retained == null:
			return _failure(&"RUN_REPLAY_STORE_IO_FAILED")
		retained_bytes += retained.get_length()
		retained.close()
		if retained_bytes + int(chunk.compressed_size) > MAX_PHYSICAL_BYTES:
			return _failure(&"RUN_REPLAY_STORE_CAPACITY")
	var temporary := path + "." + Crypto.new().generate_random_bytes(8).hex_encode() + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _failure(&"RUN_REPLAY_STORE_IO_FAILED")
	file.store_buffer(chunk.bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or Codec.byte_digest(FileAccess.get_file_as_bytes(temporary)) != chunk.compressed_sha256:
		DirAccess.remove_absolute(temporary)
		return _failure(&"RUN_REPLAY_STORE_IO_FAILED")
	if DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
		return _failure(&"RUN_REPLAY_STORE_IO_FAILED")
	return _success()


func _read_chunk(descriptor: Dictionary) -> Dictionary:
	var file := FileAccess.open(_directory.path_join(str(descriptor.compressed_sha256) + ".zst"), FileAccess.READ)
	if file == null or file.get_length() != int(descriptor.compressed_size):
		return _failure(&"RUN_REPLAY_STORE_CHUNK_MISSING")
	var bytes := file.get_buffer(int(descriptor.compressed_size))
	file.close()
	if bytes.size() != int(descriptor.compressed_size) or Codec.byte_digest(bytes) != descriptor.compressed_sha256:
		return _failure(&"RUN_REPLAY_STORE_CHUNK_CORRUPT")
	var chunk := descriptor.duplicate(true)
	chunk.bytes = bytes
	return _success({"chunk": chunk})


static func _validate(value: Variant) -> Dictionary:
	if not value is Dictionary or not _fields(value, ["schema_version", "revision", "entries"]) or not _integer(value.schema_version, 1, 1) or not _integer(value.revision, 0, 2147483647) or not value.entries is Array or value.entries.size() > MAX_ENTRIES:
		return _failure(&"RUN_REPLAY_STORE_MANIFEST_INVALID")
	var result := {"schema_version": 1, "revision": int(value.revision), "entries": []}
	var ids: Dictionary = {}
	var archive_bytes := 0
	for source: Variant in value.entries:
		if not source is Dictionary or not _fields(source, ENTRY_FIELDS) or not Recorder._is_sha256(source.id) or ids.has(source.id) or not _integer(source.seed, -2147483648, 2147483647) or source.status not in STATUSES or not _integer(source.observation_count, 0, MAX_OBSERVATIONS) or not _integer(source.compressed_bytes, 0, MAX_RUN_BYTES) or not source.chunks is Array or source.chunks.size() > MAX_CHUNKS or not _decode_identity(source).ok:
			return _failure(&"RUN_REPLAY_STORE_MANIFEST_INVALID")
		ids[source.id] = true
		var entry: Dictionary = source.duplicate(true)
		entry.seed = int(source.seed)
		entry.observation_count = int(source.observation_count)
		entry.compressed_bytes = int(source.compressed_bytes)
		entry.chunks = []
		var sequence := 0
		var compressed_bytes := 0
		for source_chunk: Variant in source.chunks:
			if not source_chunk is Dictionary or not _fields(source_chunk, DESCRIPTOR_FIELDS) or source_chunk.schema_id != Codec.SCHEMA_ID or not _integer(source_chunk.schema_version, 1, 1) or not _integer(source_chunk.first_sequence, sequence, sequence) or not _integer(source_chunk.observation_count, 1, Codec.MAX_OBSERVATIONS) or not _integer(source_chunk.last_sequence, sequence + int(source_chunk.observation_count) - 1, sequence + int(source_chunk.observation_count) - 1) or not _integer(source_chunk.raw_size, 1, Codec.MAX_RAW_BYTES) or not _integer(source_chunk.compressed_size, 1, Codec.MAX_COMPRESSED_BYTES) or not Recorder._is_sha256(source_chunk.raw_sha256) or not Recorder._is_sha256(source_chunk.compressed_sha256):
				return _failure(&"RUN_REPLAY_STORE_MANIFEST_INVALID")
			var chunk: Dictionary = source_chunk.duplicate(true)
			for field: String in ["schema_version", "first_sequence", "last_sequence", "observation_count", "raw_size", "compressed_size"]:
				chunk[field] = int(chunk[field])
			entry.chunks.append(chunk)
			sequence += int(chunk.observation_count)
			compressed_bytes += int(chunk.compressed_size)
		if sequence != entry.observation_count or compressed_bytes != entry.compressed_bytes or entry.status == "COMPLETE" and sequence == 0:
			return _failure(&"RUN_REPLAY_STORE_MANIFEST_INVALID")
		archive_bytes += compressed_bytes
		if archive_bytes > MAX_ARCHIVE_BYTES:
			return _failure(&"RUN_REPLAY_STORE_CAPACITY")
		result.entries.append(entry)
	return _success({"manifest": result})


static func _decode_identity(entry: Dictionary) -> Dictionary:
	if not entry.get("identity_base64") is String or entry.identity_base64.length() % 4 != 0 or entry.identity_base64.length() > MAX_IDENTITY_BYTES * 2 or not Recorder._is_sha256(entry.get("identity_sha256")):
		return _failure(&"RUN_REPLAY_STORE_IDENTITY_INVALID")
	var bytes := Marshalls.base64_to_raw(entry.identity_base64)
	if bytes.is_empty() or bytes.size() > MAX_IDENTITY_BYTES or Codec.byte_digest(bytes) != entry.identity_sha256:
		return _failure(&"RUN_REPLAY_STORE_IDENTITY_INVALID")
	var value: Variant = bytes_to_var(bytes)
	if not value is Dictionary or not Codec._safe(value) or Recorder.validate_full_player_identity(value).is_empty():
		return _failure(&"RUN_REPLAY_STORE_IDENTITY_INVALID")
	return _success({"identity": value})


func _index(id: String) -> int:
	if Recorder._is_sha256(id):
		for index: int in range(_manifest.get("entries", []).size()):
			if _manifest.entries[index].id == id:
				return index
	return -1


func _entry(id: String) -> Dictionary:
	var index := _index(id)
	return _manifest.entries[index].duplicate(true) if index >= 0 else {}


static func _empty() -> Dictionary:
	return {"schema_version": 1, "revision": 0, "entries": []}


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and value >= minimum and value <= maximum and float(value) == floorf(float(value))


static func _fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


static func _same(left: Variant, right: Variant) -> bool:
	return Envelope._is_json_compatible(left) and Envelope._is_json_compatible(right) and Envelope._json_round_trip(left) == Envelope._json_round_trip(right)


func _finish_failure(code: StringName) -> Dictionary:
	_busy = false
	return _failure(code)


static func _success(context: Dictionary = {}) -> Dictionary:
	return {"ok": true, "code": &"OK", "context": context.duplicate(true)}


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
