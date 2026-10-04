class_name DataOnlyPackInstaller
extends RefCounted

const Descriptor := preload("res://scripts/content/content_pack_descriptor.gd")
const FileOps := preload("res://scripts/save/save_file_ops.gd")
const MAX_FILES := 256
const MAX_FILE_BYTES := 16 * 1024 * 1024
const MAX_TOTAL_BYTES := 64 * 1024 * 1024
const MAX_DESCRIPTOR_BYTES := 256 * 1024
const ASSET_EXTENSIONS := ["json", "png", "ogg", "wav"]
const EXECUTABLE_FIELDS := ["script", "script_path", "script_source", "callable", "expression", "gdscript", "scene_path", "resource_path", "native_library", "code"]
const EXECUTABLE_EXTENSIONS := ["gd", "gdc", "tscn", "scn", "tres", "res", "dll", "dylib", "so", "exe", "sh", "bat", "svg"]
var _root := ""
var _file_ops = FileOps.new()


func configure(root: String) -> Dictionary:
	if root.is_empty():
		return _failure(&"INVALID_ARGUMENT", {"field": "storage_root"})
	var absolute := ProjectSettings.globalize_path(root).simplify_path()
	if not absolute.is_absolute_path() or _is_link(absolute):
		return _failure(&"UNSAFE_PATH", {"path": root})
	for child: String in ["packs", "staging"]:
		var path := absolute.path_join(child)
		if _is_link(path):
			return _failure(&"UNSAFE_PATH", {"path": path})
		var made = _file_ops.ensure_directory(path)
		if not made.ok:
			return _failure(made.code, made.metadata)
	_root = absolute
	return _success()


func inspect(source_directory: String) -> Dictionary:
	var captured := _capture(source_directory)
	if not captured.ok:
		return captured
	return _success({"descriptor": captured.context.descriptor.duplicate(true)})


func install(source_directory: String) -> Dictionary:
	var prepared := prepare(source_directory)
	if not prepared.ok or not prepared.context.get("prepared", false):
		return prepared
	return commit_prepared(str(prepared.context.descriptor.fingerprint_sha256))


func prepare(source_directory: String) -> Dictionary:
	if _root.is_empty():
		return _failure(&"NOT_CONFIGURED")
	if not _storage_is_safe():
		return _failure(&"UNSAFE_PATH", {"path": _root})
	var captured := _capture(source_directory)
	if not captured.ok:
		return captured
	var descriptor: Dictionary = captured.context.descriptor
	var fingerprint := str(descriptor.fingerprint_sha256)
	var destination := _root.path_join("packs").path_join(fingerprint)
	if DirAccess.dir_exists_absolute(destination):
		var existing := _capture(destination)
		if existing.ok and existing.context.descriptor.fingerprint_sha256 == fingerprint:
			return _success({"descriptor": existing.context.descriptor, "path": destination, "installed": false, "prepared": false})
		return _failure(&"INSTALLATION_CONFLICT", {"path": destination})
	var staging := _root.path_join("staging").path_join(fingerprint)
	if _is_link(staging):
		return _failure(&"UNSAFE_PATH", {"path": staging})
	var removed := _remove_owned_tree(staging)
	if not removed.ok:
		return removed
	var bytes_by_path: Dictionary = captured.context.bytes_by_path
	for relative_path: String in bytes_by_path:
		var written := _write_bytes(staging.path_join(relative_path), bytes_by_path[relative_path])
		if not written.ok:
			_remove_owned_tree(staging)
			return written
	var staged := _capture(staging)
	if not staged.ok or staged.context.descriptor.fingerprint_sha256 != fingerprint:
		_remove_owned_tree(staging)
		return _failure(&"STAGING_VERIFICATION_FAILED", {"source": staged})
	return _success({"descriptor": staged.context.descriptor, "path": staging, "installed": false, "prepared": true})


func commit_prepared(fingerprint: String) -> Dictionary:
	if _root.is_empty() or not Descriptor._matches(Descriptor.DIGEST_PATTERN, fingerprint):
		return _failure(&"INVALID_ARGUMENT", {"field": "fingerprint"})
	var staging := _root.path_join("staging").path_join(fingerprint)
	var destination := _root.path_join("packs").path_join(fingerprint)
	if _is_link(staging.get_base_dir()) or _is_link(destination.get_base_dir()):
		return _failure(&"UNSAFE_PATH")
	var staged := _capture(staging)
	if not staged.ok or str(staged.context.descriptor.fingerprint_sha256) != fingerprint:
		return _failure(&"STAGING_VERIFICATION_FAILED", {"source": staged})
	if DirAccess.dir_exists_absolute(destination) or _is_link(destination):
		return _failure(&"INSTALLATION_CONFLICT", {"path": destination})
	var promoted := DirAccess.rename_absolute(staging, destination)
	if promoted != OK:
		_remove_owned_tree(staging)
		return _failure(&"IO_ERROR", {"operation": "promote_installation", "error": promoted})
	var retained := _capture(destination)
	if not retained.ok:
		return _failure(&"INSTALLATION_VERIFICATION_FAILED", {"source": retained})
	return _success({"descriptor": retained.context.descriptor, "path": destination, "installed": true})


func discard_prepared(fingerprint: String) -> Dictionary:
	if _root.is_empty() or not Descriptor._matches(Descriptor.DIGEST_PATTERN, fingerprint):
		return _failure(&"INVALID_ARGUMENT", {"field": "fingerprint"})
	return _remove_owned_tree(_root.path_join("staging").path_join(fingerprint))


func scan() -> Dictionary:
	if _root.is_empty():
		return _failure(&"NOT_CONFIGURED")
	var packs_path := _root.path_join("packs")
	if _is_link(packs_path):
		return _failure(&"UNSAFE_PATH", {"path": packs_path})
	var directory := DirAccess.open(packs_path)
	if directory == null:
		return _failure(&"IO_ERROR", {"path": packs_path})
	var names: Array[String] = []
	for name: String in directory.get_directories():
		names.append(name)
	names.sort()
	var installations: Dictionary = {}
	var diagnostics: Array[Dictionary] = []
	var duplicate_ids: Dictionary = {}
	for name: String in names:
		var path := packs_path.path_join(name)
		if not Descriptor._matches(Descriptor.DIGEST_PATTERN, name):
			diagnostics.append({"code": "UNRECOGNIZED_INSTALLATION", "directory": name})
			continue
		var inspected := inspect(path)
		if not inspected.ok or inspected.context.descriptor.fingerprint_sha256 != name:
			diagnostics.append({"code": "INVALID_INSTALLATION", "directory": name, "source": inspected})
			continue
		var descriptor: Dictionary = inspected.context.descriptor
		var id := str(descriptor.pack_id)
		if installations.has(id):
			duplicate_ids[id] = true
			diagnostics.append({"code": "DUPLICATE_INSTALLATION", "pack_id": id})
		else:
			installations[id] = descriptor.duplicate(true)
	for id: String in duplicate_ids:
		installations.erase(id)
	return _success({"installations": installations, "diagnostics": diagnostics})


func uninstall(fingerprint: String) -> Dictionary:
	if _root.is_empty() or not Descriptor._matches(Descriptor.DIGEST_PATTERN, fingerprint):
		return _failure(&"INVALID_ARGUMENT", {"field": "fingerprint"})
	var path := _root.path_join("packs").path_join(fingerprint)
	if _is_link(path) or _is_link(path.get_base_dir()):
		return _failure(&"UNSAFE_PATH", {"path": path})
	return _remove_owned_tree(path)


func _capture(source_directory: String) -> Dictionary:
	var source := ProjectSettings.globalize_path(source_directory).simplify_path()
	if not source.is_absolute_path() or not DirAccess.dir_exists_absolute(source) or _is_link(source):
		return _failure(&"UNSAFE_PATH", {"path": source_directory})
	var descriptor_path := source.path_join("pack.json")
	var pack_bytes := _read_bytes(source, "pack.json", MAX_DESCRIPTOR_BYTES)
	if not pack_bytes.ok:
		return pack_bytes
	var parsed: Variant = JSON.parse_string((pack_bytes.context.bytes as PackedByteArray).get_string_from_utf8())
	if not parsed is Dictionary:
		return _failure(&"INVALID_PACK", {"file": "pack.json"})
	var validation := Descriptor._validate_source(parsed, descriptor_path)
	if not validation.ok:
		return _failure(validation.code, validation.context)
	var descriptor: Dictionary = parsed.duplicate(true)
	var paths: Array[String] = Descriptor._declared_paths(descriptor)
	if paths.size() > MAX_FILES or paths.has("pack.json"):
		return _failure(&"INSTALL_LIMIT", {"field": "declared_files"})
	if paths.size() != descriptor.integrity_hashes.size():
		return _failure(&"INVALID_PACK", {"field": "integrity_hashes"})
	var bytes_by_path: Dictionary = {"pack.json": pack_bytes.context.bytes}
	var total: int = pack_bytes.context.bytes.size()
	for relative_path: String in paths:
		if not descriptor.integrity_hashes.has(relative_path):
			return _failure(&"INTEGRITY_MISSING", {"file": relative_path})
		var extension := relative_path.get_extension().to_lower()
		var supported: bool = (descriptor.content_manifest.has(relative_path) and extension == "json") or (descriptor.localization_sources.has(relative_path) and extension == "csv") or (descriptor.asset_manifest.has(relative_path) and ASSET_EXTENSIONS.has(extension))
		if not supported or EXECUTABLE_EXTENSIONS.has(extension):
			return _failure(&"EXECUTABLE_PACK_UNSUPPORTED", {"file": relative_path})
		var captured := _read_bytes(source, relative_path, MAX_FILE_BYTES)
		if not captured.ok:
			return captured
		var bytes: PackedByteArray = captured.context.bytes
		total += bytes.size()
		if total > MAX_TOTAL_BYTES:
			return _failure(&"INSTALL_LIMIT", {"field": "total_bytes"})
		if Descriptor._sha256_bytes(bytes) != str(descriptor.integrity_hashes[relative_path]):
			return _failure(&"INTEGRITY_MISMATCH", {"file": relative_path})
		if extension == "json":
			var json_value: Variant = JSON.parse_string(bytes.get_string_from_utf8())
			if json_value == null or not _data_is_safe(json_value):
				return _failure(&"EXECUTABLE_PACK_UNSUPPORTED", {"file": relative_path})
		bytes_by_path[relative_path] = bytes
	descriptor["source_path"] = descriptor_path
	descriptor["root_path"] = source
	descriptor["required_pack"] = false
	descriptor["fingerprint_sha256"] = Descriptor.canonical_digest(parsed)
	return _success({"descriptor": descriptor.duplicate(true), "bytes_by_path": bytes_by_path})


func _read_bytes(root: String, relative_path: String, limit: int) -> Dictionary:
	var path := root
	for component: String in relative_path.split("/"):
		path = path.path_join(component)
		if _is_link(path):
			return _failure(&"UNSAFE_PATH", {"file": relative_path})
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure(&"IO_ERROR", {"file": relative_path, "error": FileAccess.get_open_error()})
	if file.get_length() > limit:
		file.close()
		return _failure(&"INSTALL_LIMIT", {"file": relative_path})
	var bytes := file.get_buffer(file.get_length())
	var error := file.get_error()
	file.close()
	if error != OK:
		return _failure(&"IO_ERROR", {"file": relative_path, "error": error})
	return _success({"bytes": bytes})


func _data_is_safe(value: Variant, depth: int = 0) -> bool:
	if depth > 32:
		return false
	if value is Dictionary:
		for key: Variant in value:
			if typeof(key) != TYPE_STRING or EXECUTABLE_FIELDS.has(str(key).to_lower()) or not _data_is_safe(value[key], depth + 1):
				return false
	elif value is Array:
		for child: Variant in value:
			if not _data_is_safe(child, depth + 1):
				return false
	elif typeof(value) == TYPE_STRING:
		var text := str(value).to_lower()
		if EXECUTABLE_EXTENSIONS.has(text.get_extension()) or text.begins_with("uid://"):
			return false
	elif typeof(value) == TYPE_FLOAT and not is_finite(float(value)):
		return false
	return true


func _write_bytes(path: String, bytes: PackedByteArray) -> Dictionary:
	var made = _file_ops.ensure_directory(path.get_base_dir())
	if not made.ok:
		return _failure(made.code, made.metadata)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _failure(&"IO_ERROR", {"path": path})
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	return _success() if error == OK else _failure(&"IO_ERROR", {"path": path, "error": error})


func _is_link(path: String) -> bool:
	var parent := DirAccess.open(path.get_base_dir())
	return parent != null and parent.is_link(path.get_file())


func _remove_owned_tree(path: String) -> Dictionary:
	if _root.is_empty() or not _storage_is_safe() or not (path.begins_with(_root.path_join("packs") + "/") or path.begins_with(_root.path_join("staging") + "/")):
		return _failure(&"UNSAFE_PATH", {"path": path})
	if _is_link(path) or FileAccess.file_exists(path):
		var removed := DirAccess.remove_absolute(path)
		return _success({"removed": true}) if removed == OK else _failure(&"IO_ERROR", {"error": removed})
	if not DirAccess.dir_exists_absolute(path):
		return _success({"removed": false})
	var directory := DirAccess.open(path)
	if directory == null:
		return _failure(&"IO_ERROR", {"path": path})
	directory.include_hidden = true
	var children: Array[String] = []
	children.assign(directory.get_files())
	for child: String in directory.get_directories():
		children.append(child)
	for child: String in children:
		var result := _remove_owned_tree(path.path_join(child))
		if not result.ok:
			return result
	var removed := DirAccess.remove_absolute(path)
	return _success({"removed": true}) if removed == OK else _failure(&"IO_ERROR", {"error": removed})


func _storage_is_safe() -> bool:
	return not _is_link(_root) and not _is_link(_root.path_join("packs")) and not _is_link(_root.path_join("staging"))


func _success(context: Dictionary = {}) -> Dictionary:
	return {"ok": true, "code": &"OK", "context": context.duplicate(true)}


func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context.duplicate(true)}
