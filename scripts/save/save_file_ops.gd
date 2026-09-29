class_name SaveFileOps
extends RefCounted

const SaveResultScript := preload("res://scripts/save/save_result.gd")


func ensure_directory(path: String):
	if path.strip_edges().is_empty():
		return _invalid_path(path)
	var error := DirAccess.make_dir_recursive_absolute(path)
	if error != OK and error != ERR_ALREADY_EXISTS:
		return _io_failure("make_directory", path, error)
	return SaveResultScript.success({}, {"path": path})


func read_utf8(path: String):
	if path.strip_edges().is_empty():
		return _invalid_path(path)
	if not FileAccess.file_exists(path):
		return SaveResultScript.failure(&"NOT_FOUND", {"path": path})
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _io_failure("open_read", path, FileAccess.get_open_error())
	var contents := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK:
		return _io_failure("read", path, read_error)
	return SaveResultScript.success(contents, {
		"path": path,
		"byte_count": contents.to_utf8_buffer().size(),
	})


func write_utf8(path: String, contents: String):
	if path.strip_edges().is_empty():
		return _invalid_path(path)
	var directory_result = ensure_directory(path.get_base_dir())
	if not directory_result.ok:
		return directory_result
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _io_failure("open_write", path, FileAccess.get_open_error())
	file.store_string(contents)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return _io_failure("write", path, write_error)
	return SaveResultScript.success({}, {
		"path": path,
		"byte_count": contents.to_utf8_buffer().size(),
	})


func copy_file(source_path: String, destination_path: String):
	if source_path.strip_edges().is_empty() or destination_path.strip_edges().is_empty():
		return _invalid_path(destination_path, {"source_path": source_path})
	if not FileAccess.file_exists(source_path):
		return SaveResultScript.failure(&"NOT_FOUND", {"path": source_path})
	var directory_result = ensure_directory(destination_path.get_base_dir())
	if not directory_result.ok:
		return directory_result
	var error := DirAccess.copy_absolute(source_path, destination_path)
	if error != OK:
		return _io_failure("copy", destination_path, error, {"source_path": source_path})
	return SaveResultScript.success({}, {
		"source_path": source_path,
		"path": destination_path,
	})


func rename_file(source_path: String, destination_path: String):
	if source_path.strip_edges().is_empty() or destination_path.strip_edges().is_empty():
		return _invalid_path(destination_path, {"source_path": source_path})
	if not FileAccess.file_exists(source_path):
		return SaveResultScript.failure(&"NOT_FOUND", {"path": source_path})
	var directory_result = ensure_directory(destination_path.get_base_dir())
	if not directory_result.ok:
		return directory_result
	var error := DirAccess.rename_absolute(source_path, destination_path)
	if error != OK:
		return _io_failure("rename", destination_path, error, {"source_path": source_path})
	return SaveResultScript.success({}, {
		"source_path": source_path,
		"path": destination_path,
	})


func remove_file(path: String):
	if path.strip_edges().is_empty():
		return _invalid_path(path)
	if not FileAccess.file_exists(path):
		return SaveResultScript.success({}, {"path": path, "removed": false})
	var error := DirAccess.remove_absolute(path)
	if error != OK:
		return _io_failure("remove", path, error)
	return SaveResultScript.success({}, {"path": path, "removed": true})


func quarantine(source_path: String, quarantine_directory: String, candidate_kind: StringName, reason: String):
	if not FileAccess.file_exists(source_path):
		return SaveResultScript.failure(&"NOT_FOUND", {
			"path": source_path,
			"candidate_kind": str(candidate_kind),
		})
	var directory_result = ensure_directory(quarantine_directory)
	if not directory_result.ok:
		return directory_result
	var sequence := _next_quarantine_sequence(quarantine_directory)
	var destination_name := "%06d_%s_%s.bin" % [
		sequence,
		_sanitize_component(str(candidate_kind)),
		_sanitize_component(reason),
	]
	var destination_path := quarantine_directory.path_join(destination_name)
	var rename_result = rename_file(source_path, destination_path)
	if not rename_result.ok:
		var copy_result = copy_file(source_path, destination_path)
		if not copy_result.ok:
			return copy_result
		var remove_result = remove_file(source_path)
		if not remove_result.ok:
			remove_file(destination_path)
			return remove_result
	return SaveResultScript.success({}, {
		"source_path": source_path,
		"path": destination_path,
		"candidate_kind": str(candidate_kind),
		"reason": reason,
		"quarantine_sequence": sequence,
	})


func remove_tree(path: String):
	if path.strip_edges().is_empty():
		return _invalid_path(path)
	if FileAccess.file_exists(path):
		return remove_file(path)
	if not DirAccess.dir_exists_absolute(path):
		return SaveResultScript.success({}, {"path": path, "removed": false})
	var directory := DirAccess.open(path)
	if directory == null:
		return _io_failure("open_directory", path, DirAccess.get_open_error())
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry not in [".", ".."]:
			var child_result = remove_tree(path.path_join(entry))
			if not child_result.ok:
				directory.list_dir_end()
				return child_result
		entry = directory.get_next()
	directory.list_dir_end()
	var remove_error := DirAccess.remove_absolute(path)
	if remove_error != OK:
		return _io_failure("remove_directory", path, remove_error)
	return SaveResultScript.success({}, {"path": path, "removed": true})


func _next_quarantine_sequence(directory_path: String) -> int:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return 1
	var highest := 0
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not directory.current_is_dir():
			var separator := entry.find("_")
			if separator > 0:
				var prefix := entry.substr(0, separator)
				if prefix.is_valid_int():
					highest = maxi(highest, int(prefix))
		entry = directory.get_next()
	directory.list_dir_end()
	return highest + 1


func _sanitize_component(value: String) -> String:
	var normalized := value.to_lower()
	var output := ""
	for index: int in range(normalized.length()):
		var codepoint := normalized.unicode_at(index)
		if (codepoint >= 97 and codepoint <= 122) or (codepoint >= 48 and codepoint <= 57):
			output += normalized.substr(index, 1)
		elif output.is_empty() or not output.ends_with("-"):
			output += "-"
	output = output.trim_prefix("-").trim_suffix("-")
	return output.substr(0, 48) if not output.is_empty() else "unknown"


func _invalid_path(path: String, extra_metadata: Dictionary = {}):
	var metadata := extra_metadata.duplicate(true)
	metadata["field"] = "path"
	metadata["value"] = path
	return SaveResultScript.failure(&"INVALID_ARGUMENT", metadata)


func _io_failure(operation: String, path: String, error: int, extra_metadata: Dictionary = {}):
	var metadata := extra_metadata.duplicate(true)
	metadata["operation"] = operation
	metadata["path"] = path
	metadata["error"] = error
	return SaveResultScript.failure(&"IO_ERROR", metadata)
