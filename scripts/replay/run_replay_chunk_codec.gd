extends RefCounted

const Recorder := preload("res://scripts/replay/replay_recorder.gd")
const SCHEMA_ID := "planewalker.run_replay_chunk"
const MAX_OBSERVATIONS := 120
const MAX_RAW_BYTES := 32 * 1024 * 1024
const MAX_COMPRESSED_BYTES := 8 * 1024 * 1024
const MAX_DEPTH := 32
const MAX_PATCHES := 32768
const FIELDS := ["schema_id", "schema_version", "first_sequence", "last_sequence", "observation_count", "raw_size", "compressed_size", "raw_sha256", "compressed_sha256", "bytes"]


static func encode(observations: Array[Dictionary]) -> Dictionary:
	if observations.is_empty() or observations.size() > MAX_OBSERVATIONS:
		return _failure(&"RUN_REPLAY_CHUNK_INVALID")
	var first: Variant = observations[0].get("sequence")
	if not _integer(first, 0, 2147483647 - observations.size() + 1):
		return _failure(&"RUN_REPLAY_CHUNK_INVALID")
	var deltas: Array[Dictionary] = []
	for index: int in range(observations.size()):
		var current: Dictionary = observations[index]
		if current.get("sequence") != first + index or typeof(current.get("sequence")) != TYPE_INT or not _safe(current):
			return _failure(&"RUN_REPLAY_CHUNK_INVALID")
		if index > 0:
			var changes: Array[Dictionary] = []
			var removed: Array[Array] = []
			_difference(observations[index - 1], current, [], changes, removed)
			if changes.size() + removed.size() > MAX_PATCHES:
				return _failure(&"RUN_REPLAY_CHUNK_SIZE_INVALID")
			deltas.append({"sequence": int(current.sequence), "removed": removed, "set": changes, "snapshot_sha256": byte_digest(var_to_bytes(current))})
	var payload := {"schema_id": SCHEMA_ID, "schema_version": 1, "keyframe": observations[0].duplicate(true), "deltas": deltas}
	var raw := var_to_bytes(payload)
	if raw.is_empty() or raw.size() > MAX_RAW_BYTES:
		return _failure(&"RUN_REPLAY_CHUNK_SIZE_INVALID")
	var compressed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	if compressed.is_empty() or compressed.size() > MAX_COMPRESSED_BYTES:
		return _failure(&"RUN_REPLAY_CHUNK_SIZE_INVALID")
	return _success({"chunk": {"schema_id": SCHEMA_ID, "schema_version": 1, "first_sequence": first, "last_sequence": first + observations.size() - 1, "observation_count": observations.size(), "raw_size": raw.size(), "compressed_size": compressed.size(), "raw_sha256": byte_digest(raw), "compressed_sha256": byte_digest(compressed), "bytes": compressed}})


static func decode(chunk: Dictionary) -> Dictionary:
	if not _fields(chunk, FIELDS) or chunk.schema_id != SCHEMA_ID or typeof(chunk.schema_version) != TYPE_INT or chunk.schema_version != 1:
		return _failure(&"RUN_REPLAY_CHUNK_INVALID")
	if not _integer(chunk.first_sequence, 0, 2147483647) or not _integer(chunk.observation_count, 1, MAX_OBSERVATIONS) or typeof(chunk.last_sequence) != TYPE_INT or chunk.last_sequence != chunk.first_sequence + chunk.observation_count - 1:
		return _failure(&"RUN_REPLAY_CHUNK_INVALID")
	if not _integer(chunk.raw_size, 1, MAX_RAW_BYTES) or not _integer(chunk.compressed_size, 1, MAX_COMPRESSED_BYTES) or not chunk.bytes is PackedByteArray or chunk.bytes.size() != chunk.compressed_size:
		return _failure(&"RUN_REPLAY_CHUNK_SIZE_INVALID")
	if not Recorder._is_sha256(chunk.raw_sha256) or not Recorder._is_sha256(chunk.compressed_sha256) or byte_digest(chunk.bytes) != chunk.compressed_sha256:
		return _failure(&"RUN_REPLAY_CHUNK_DIGEST_INVALID")
	var raw: PackedByteArray = chunk.bytes.decompress(chunk.raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != chunk.raw_size or byte_digest(raw) != chunk.raw_sha256:
		return _failure(&"RUN_REPLAY_CHUNK_DIGEST_INVALID")
	var payload: Variant = bytes_to_var(raw)
	if not payload is Dictionary or not _fields(payload, ["schema_id", "schema_version", "keyframe", "deltas"]) or payload.schema_id != SCHEMA_ID or typeof(payload.schema_version) != TYPE_INT or payload.schema_version != 1 or not payload.keyframe is Dictionary or not payload.deltas is Array or payload.deltas.size() != chunk.observation_count - 1 or not _safe(payload.keyframe):
		return _failure(&"RUN_REPLAY_CHUNK_INVALID")
	if typeof(payload.keyframe.get("sequence")) != TYPE_INT or payload.keyframe.sequence != chunk.first_sequence:
		return _failure(&"RUN_REPLAY_CHUNK_INVALID")
	var observations: Array[Dictionary] = [payload.keyframe.duplicate(true)]
	for index: int in range(payload.deltas.size()):
		var result := _apply_delta(observations[-1], payload.deltas[index], int(chunk.first_sequence) + index + 1)
		if not result.ok:
			return result
		observations.append(result.context.observation)
	return _success({"observations": observations})


static func byte_digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


static func _difference(before: Variant, after: Variant, path: Array, changes: Array[Dictionary], removed: Array[Array]) -> void:
	if var_to_bytes(before) == var_to_bytes(after):
		return
	if before is Dictionary and after is Dictionary and _dictionary_types_match(before, after) and _ordered_keys_match(before, after):
		for key: Variant in before:
			if not after.has(key):
				var removal := path.duplicate()
				removal.append(key)
				removed.append(removal)
		for key: Variant in after:
			var child_path := path.duplicate()
			child_path.append(key)
			if before.has(key):
				_difference(before[key], after[key], child_path, changes, removed)
			else:
				changes.append({"path": child_path, "value": _copy(after[key])})
	else:
		changes.append({"path": path.duplicate(), "value": _copy(after)})


static func _ordered_keys_match(before: Dictionary, after: Dictionary) -> bool:
	var keys: Array = []
	for key: Variant in before:
		if after.has(key):
			keys.append(key)
	for key: Variant in after:
		if not before.has(key):
			keys.append(key)
	return var_to_bytes(keys) == var_to_bytes(after.keys())


static func _dictionary_types_match(before: Dictionary, after: Dictionary) -> bool:
	return before.get_typed_key_builtin() == after.get_typed_key_builtin() and before.get_typed_value_builtin() == after.get_typed_value_builtin()


static func _apply_delta(before: Dictionary, delta: Variant, sequence: int) -> Dictionary:
	if not delta is Dictionary or not _fields(delta, ["sequence", "removed", "set", "snapshot_sha256"]) or typeof(delta.sequence) != TYPE_INT or delta.sequence != sequence or not delta.removed is Array or not delta.set is Array or delta.removed.size() + delta.set.size() > MAX_PATCHES or not Recorder._is_sha256(delta.snapshot_sha256):
		return _failure(&"RUN_REPLAY_CHUNK_DELTA_INVALID")
	var paths: Array[Array] = []
	for path: Variant in delta.removed:
		if not _unique_path(path, paths) or path.is_empty():
			return _failure(&"RUN_REPLAY_CHUNK_DELTA_INVALID")
		paths.append(path)
	for patch: Variant in delta.set:
		if not patch is Dictionary or not _fields(patch, ["path", "value"]) or not _unique_path(patch.path, paths) or not _safe(patch.value):
			return _failure(&"RUN_REPLAY_CHUNK_DELTA_INVALID")
		paths.append(patch.path)
	var candidate := before.duplicate(true)
	for path: Array in delta.removed:
		var parent: Variant = _parent(candidate, path)
		if not parent is Dictionary or not parent.has(path[-1]):
			return _failure(&"RUN_REPLAY_CHUNK_DELTA_INVALID")
		parent.erase(path[-1])
	for patch: Dictionary in delta.set:
		if patch.path.is_empty():
			if not patch.value is Dictionary:
				return _failure(&"RUN_REPLAY_CHUNK_DELTA_INVALID")
			candidate = patch.value.duplicate(true)
		else:
			var parent: Variant = _parent(candidate, patch.path)
			if not parent is Dictionary:
				return _failure(&"RUN_REPLAY_CHUNK_DELTA_INVALID")
			parent[patch.path[-1]] = _copy(patch.value)
	if typeof(candidate.get("sequence")) != TYPE_INT or candidate.sequence != sequence or not _safe(candidate) or byte_digest(var_to_bytes(candidate)) != delta.snapshot_sha256:
		return _failure(&"RUN_REPLAY_CHUNK_DELTA_INVALID")
	return _success({"observation": candidate})


static func _unique_path(path: Variant, existing: Array[Array]) -> bool:
	if not path is Array or path.size() > MAX_DEPTH:
		return false
	for key: Variant in path:
		if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME, TYPE_INT]:
			return false
	for prior: Array in existing:
		var common := mini(path.size(), prior.size())
		var prefix := true
		for index: int in range(common):
			if var_to_bytes(path[index]) != var_to_bytes(prior[index]):
				prefix = false
				break
		if prefix:
			return false
	return true


static func _parent(root: Dictionary, path: Array) -> Variant:
	var current: Variant = root
	for index: int in range(path.size() - 1):
		if not current is Dictionary or not current.has(path[index]):
			return null
		current = current[path[index]]
	return current


static func _safe(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_DEPTH:
		return false
	if value is Dictionary:
		if value.get_typed_key_builtin() == TYPE_OBJECT or value.get_typed_value_builtin() == TYPE_OBJECT:
			return false
		for key: Variant in value:
			if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME, TYPE_INT] or not _safe(value[key], depth + 1):
				return false
		return true
	if value is Array:
		if value.get_typed_builtin() == TYPE_OBJECT:
			return false
		for child: Variant in value:
			if not _safe(child, depth + 1):
				return false
		return true
	if value is Vector2:
		return is_finite(value.x) and is_finite(value.y)
	if value is Vector3:
		return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
	if value is Vector4:
		return is_finite(value.x) and is_finite(value.y) and is_finite(value.z) and is_finite(value.w)
	if value is Rect2:
		return _safe(value.position, depth + 1) and _safe(value.size, depth + 1)
	if value is Transform2D:
		return _safe(value.x, depth + 1) and _safe(value.y, depth + 1) and _safe(value.origin, depth + 1)
	if value is Basis:
		return _safe(value.x, depth + 1) and _safe(value.y, depth + 1) and _safe(value.z, depth + 1)
	if value is Transform3D:
		return _safe(value.basis, depth + 1) and _safe(value.origin, depth + 1)
	if value is Quaternion:
		return is_finite(value.x) and is_finite(value.y) and is_finite(value.z) and is_finite(value.w)
	if value is Plane:
		return _safe(value.normal, depth + 1) and is_finite(value.d)
	if value is AABB:
		return _safe(value.position, depth + 1) and _safe(value.size, depth + 1)
	if value is Projection:
		return _safe(value.x, depth + 1) and _safe(value.y, depth + 1) and _safe(value.z, depth + 1) and _safe(value.w, depth + 1)
	if value is PackedVector2Array or value is PackedVector3Array or value is PackedColorArray:
		for child: Variant in value:
			if not _safe(child, depth + 1):
				return false
		return true
	if value is Color:
		return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)
	return Recorder.replay_value_is_safe(value)


static func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value


static func _fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) == TYPE_INT and value >= minimum and value <= maximum


static func _success(context: Dictionary) -> Dictionary:
	return {"ok": true, "code": &"OK", "context": context}


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
