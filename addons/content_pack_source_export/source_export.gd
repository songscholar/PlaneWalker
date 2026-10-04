@tool
extends EditorExportPlugin

const Descriptor := preload("res://scripts/content/content_pack_descriptor.gd")
const PACK_ROOT := "res://data/content_packs"


func _get_name() -> String:
	return "ContentPackSourceIntegrity"


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	var descriptors: Array[String] = []
	if not _collect_descriptors(PACK_ROOT, descriptors) or descriptors.is_empty():
		_fail("No readable project content-pack descriptors")
		return
	var sources: Dictionary = {}
	for path: String in descriptors:
		var loaded: Dictionary = Descriptor.load_path(path, true)
		if not loaded.ok:
			_fail("Descriptor authentication refused: " + path + " " + str(loaded))
			return
		var hashes: Dictionary = loaded.descriptor.integrity_hashes
		for relative: String in hashes:
			var source_path := path.get_base_dir().path_join(relative)
			var bytes := FileAccess.get_file_as_bytes(source_path)
			var hashing := HashingContext.new()
			if hashing.start(HashingContext.HASH_SHA256) != OK or hashing.update(bytes) != OK or hashing.finish().hex_encode() != hashes[relative]:
				_fail("Source changed after descriptor authentication: " + source_path)
				return
			sources[source_path] = bytes
	# Keep source paths and native .import/.remap targets together.
	var paths := sources.keys()
	paths.sort()
	for path: String in paths:
		add_file(path, sources[path], false)
	print("CONTENT_PACK_SOURCE_EXPORT: authenticated source files=", sources.size())


func _collect_descriptors(path: String, target: Array[String]) -> bool:
	var directory := DirAccess.open(path)
	if directory == null:
		return false
	if directory.file_exists("pack.json"):
		target.append(path.path_join("pack.json"))
		return true
	var children := directory.get_directories()
	children.sort()
	for child: String in children:
		if directory.is_link(child) or not _collect_descriptors(path.path_join(child), target):
			return false
	return true


func _fail(message: String) -> void:
	get_export_platform().add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR, "Content pack integrity", message)
